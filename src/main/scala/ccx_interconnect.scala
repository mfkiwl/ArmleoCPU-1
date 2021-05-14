package armleocpu

import CacheConsts._
import Consts._
import chisel3._
import chisel3.util._

class RoundRobin(n: Int) extends Module {
    val io = IO(new Bundle{
        val req = Input(Vec(n, Bool()))
        val grant = Output(Vec(n, Bool()))
        val next = Input(Bool())
        val choice = Output(UInt(n.W))
    })
    val rotate_ptr = RegInit(0.U((log2Ceil(n)).W))
    val shift_req = (Cat(io.req.asUInt(), io.req.asUInt()) >> rotate_ptr)(n-1, 0)
    val shift_grant = Wire(Vec(n, Bool()))

    //shift_grant := 0.U

    for(i <- 0 until n) {
        shift_grant(i) := PriorityEncoder(shift_req) === i.U
    }
    val grant_comb = (Cat(shift_grant.asUInt(), shift_grant.asUInt()) << rotate_ptr)(n+n-1, n)
    
    io.choice := PriorityEncoder(grant_comb)

    io.grant := grant_comb.asBools()
    when(io.next) {
        when(io.choice === (n - 1).U) {
            rotate_ptr := 0.U
        }.otherwise {
            rotate_ptr := io.choice + 1.U
        }
    }
}


// Note: Only write-through is supported
// Note: Cache line size is 64 bytes and is fixed
// Note: This interconnect does not implement full ACE, but minimal set required by core
// Note: ReadNoSnoop is used for peripheral bus loads
//              It does not cause any Cache access
// Note: WriteNoSnoop is used to write to peripheral bus stores
// Note: The reason is that peripheral address space is separated from Cache address space
// Coherency protocols:
// Note: WriteUnique is used to write to memory. Only write-through is supported
//      CleanInvalid is issued to Cache memory
// Note: ReadShared is used by Cache to reserve line for load operations
// Note: Barrier is just transfered to all Cache lines
// Note: CRRESP[1] (ECC Error) is ignored

// TODO: Add statistics

// Note: It is expected for memory to prioritize write requests for this interconnect

// N: Shows amount of caches. Not amount of cores
class CCXInterconnect(n: Int, StatisticsBaseAddr: BigInt = BigInt("FFFFFFFF", 16), core_id_width: Int = 1) extends Module {
    val mbus_id_width = core_id_width + log2Ceil(n)

    val p = new AXIParams(64, 64, core_id_width)
    val mparams = new AXIParams(64, 64, mbus_id_width)
    

    val io = IO(new Bundle{
        val mbus = new AXIHostIF(mparams)

        val corebus = Vec(n, Flipped(new ACEHostIF(p)))
        // Even tho it's called corebus, it's actually connection to a cache of the core, which is double the amount of cores
    })

    // TODO: Keep statistics and return it when requested StatisticsBaseAddr

    

    // Shorthands:
    // TODO: In future replace with registered buffer
    val aw = VecInit(Seq.tabulate(n) (i => io.corebus(i).aw))
    val ar = VecInit(Seq.tabulate(n) (i => io.corebus(i).ar))
    val w = VecInit(Seq.tabulate(n) (i => io.corebus(i).w))
    val cr = VecInit(Seq.tabulate(n) (i => io.corebus(i).cr))
    val cd = VecInit(Seq.tabulate(n) (i => io.corebus(i).cd))

    // TODO: Add shorthands for other buses
    // val b = 
    // val r = 
    // val ac = 

    val mbus = io.mbus
    
    val arb = Module(new RoundRobin(n))

    arb.io.next := false.B

    for(i <- 0 until n) {
        arb.io.req(i)               := ar(i).valid || aw(i).valid


                aw(i).ready         := false.B
                ar(i).ready         := false.B
                w(i).ready          := false.B
                cr(i).ready         := false.B
                cd(i).ready         := false.B

        io.corebus(i).b.valid       := false.B
        io.corebus(i).b.bits        := 0.U.asTypeOf(io.corebus(i).b.bits)

        io.corebus(i).r.valid       := false.B
        io.corebus(i).r.bits        := 0.U.asTypeOf(io.corebus(i).r.bits)

        io.corebus(i).ac.valid      := false.B
        io.corebus(i).ac.bits       := 0.U.asTypeOf(io.corebus(i).ac.bits)
    }


    mbus.ar.bits            := 0.U.asTypeOf(mbus.ar.bits)
    mbus.ar.valid           := false.B
    mbus.r.ready            := false.B
    mbus.w.bits             := 0.U.asTypeOf(mbus.w.bits)
    mbus.w.valid            := false.B
    mbus.b.ready            := false.B

    val STATE_WIDTH             = 4

    val STATE_IDLE              = 0.U(STATE_WIDTH.W) // Wait for request, branch to READ/WRITE

    // Branch WRITE
    val STATE_WRITE_INVALIDATE      = 1.U(STATE_WIDTH.W) // Only for WriteUnique: Send invalidate to all cache
    val STATE_WRITE_INVALIDATE_RESP = 2.U(STATE_WIDTH.W) // Wait for response from all caches
    val STATE_WRITE_ADDRESS         = 3.U(STATE_WIDTH.W) // Send write request to mbus
    val STATE_WRITE_DATA            = 4.U(STATE_WIDTH.W) // Send write data to mbus
    val STATE_WRITE_RESPONSE        = 5.U(STATE_WIDTH.W) // Return response to requesting host
    val STATE_WRITE_WACK            = 6.U(STATE_WIDTH.W) // Wait for writeackowledge


    // Branch READ
    val STATE_READ_POLL             =  7.U(STATE_WIDTH.W) // Only for ReadShared
    val STATE_READ_RETURN_RESPONSE  =  8.U(STATE_WIDTH.W) // Only for ReadShared
    val STATE_READ_RETURN_DATA      =  9.U(STATE_WIDTH.W) // Only for ReadShared
    val STATE_READ_ADDRESS          = 10.U(STATE_WIDTH.W) // ReadShared failed cache hit /ReadNoSnoop
    val STATE_READ_RESPONSE         = 11.U(STATE_WIDTH.W) // ReadShared failed cache hit /ReadNoSnoop
    val STATE_READ_RACK             = 12.U(STATE_WIDTH.W) // Common for both paths


    val state = RegInit(STATE_IDLE)

    // address write channel
    val current_active_num = RegInit(0.U(log2Ceil(n).W))
    
    val ac_sent = Reg(Vec(n, Bool()))
    val cr_done = Reg(Vec(n, Bool()))
    val cd_done = Reg(Vec(n, Bool()))

    val data_available = RegInit(false.B) // Is data available in cache?
    val data_available_host = Reg(Vec(n, Bool()))
    
    val return_host_select = RegInit(0.U(log2Ceil(n).W))
    val return_host_select_valid = RegInit(false.B)

    val rid = Reg(UInt(core_id_width.W))

    val atomic_reserved = RegInit(false.B)
    val atomic_reservation_address = Reg(UInt(64.W))

    mbus.aw.valid       := false.B
    // Just pass data to memory
    mbus.aw.bits.addr  := aw(current_active_num).bits.addr
    mbus.aw.bits.size  := aw(current_active_num).bits.size
    mbus.aw.bits.len   := aw(current_active_num).bits.len
    mbus.aw.bits.burst := aw(current_active_num).bits.burst
    mbus.aw.bits.id    := Cat(current_active_num, aw(current_active_num).bits.id)
    mbus.aw.bits.lock  := aw(current_active_num).bits.lock
    mbus.aw.bits.cache := aw(current_active_num).bits.cache
    // TODO: In future set or clear CACHE bits accrodingly to config
    mbus.aw.bits.prot  := aw(current_active_num).bits.prot
    mbus.aw.bits.qos   := aw(current_active_num).bits.qos

    mbus.w.bits := w(current_active_num).bits

    
    // TODO: make WriteUnique
    // TODO: Add ReadShared
    // TODO: Atomic operations

    for(i <- 0 until n) {
        io.corebus(i).b.bits := mbus.b.bits
        io.corebus(i).b.bits.id := mbus.b.bits.id(core_id_width-1, 0) // TODO: May be add more user bits?
        
        // Address write
        when(state === STATE_IDLE) {
            ac_sent(i) := false.B
            cd_done(i) := false.B
            cr_done(i) := false.B
            data_available_host(i) := false.B
            data_available := false.B
            return_host_select := 0.U
            return_host_select_valid := false.B

            // Make decision on which bus to process and register request
            // Prioritize write requests
            when(aw(arb.io.choice).valid) { // If any transactions are active and granted
                when(aw(arb.io.choice).bits.isWriteUnique()) {
                    state := STATE_WRITE_INVALIDATE
                } .elsewhen (aw(arb.io.choice).bits.isWriteNoSnoop()) {
                    state := STATE_WRITE_ADDRESS
                } .otherwise {
                    printf("!ERROR! Interconnect: Error wrong write transaction")
                }
                chisel3.assert(aw(arb.io.choice).bits.burst === 0.U)
                chisel3.assert(aw(arb.io.choice).bits.size <= "b011".U) // 8/4/2/1 bytes
                chisel3.assert(aw(arb.io.choice).bits.len === 0.U) // One beat
                // TODO: Add assertion for Cache
            } .elsewhen(ar(arb.io.choice).valid) {
                when(ar(arb.io.choice).bits.isReadNoSnoop()) {
                    state := STATE_READ_ADDRESS
                    chisel3.assert(ar(arb.io.choice).bits.burst === 0.U)
                    /*when(ar(arb.io.choice).bits.lock) {
                        atomic_reserved := true.B
                        atomic_reservation_address := ar(arb.io.choice).bits.addr
                        // TODO:  Add proper assertion for transaction type to be either 32 bit or 64 bit
                        chisel3.assert(
                            (ar(arb.io.choice).bits.len === 0.U) && // Singular transfer
                                    ((ar(arb.io.choice).bits.size === "b010".U) // 4 bytes
                                    || (ar(arb.io.choice).bits.size === "b011".U)) // 8 bytes
                        )
                        // TODO: Make sure that transaction data result is only one 4 bytes / 8 bytes in length
                    }*/
                } .elsewhen (ar(arb.io.choice).bits.isReadShared()) {
                    state := STATE_READ_POLL
                    // TODO: Reservation for atomics
                    
                    chisel3.assert(ar(arb.io.choice).bits.burst === 2.U)
                    rid := ar(arb.io.choice).bits.id
                } .otherwise {
                    printf("!ERROR! Interconnect: Error wrong read transaction")
                }
                ar(arb.io.choice).ready := true.B
                assert(!ar(arb.io.choice).bits.lock, "!ERROR! Interconnect: atomics not supported yet")
            }
            arb.io.next := true.B
            current_active_num := arb.io.choice
        } .elsewhen (state === STATE_WRITE_INVALIDATE) {
            // Send invalidate to all cache
            // TODO: Test
            io.corebus(i).ac.bits.addr := aw(current_active_num).bits.addr
            io.corebus(i).ac.bits.snoop := "b1001".U
            // TODO: Maybe MakeInvalid would be better?
            // This should work because Cache is write-through so dirty bits are impossible
            io.corebus(i).ac.bits.prot := aw(current_active_num).bits.prot

            when(current_active_num =/= i.U) {
                // For snooped hosts wait for ready
                io.corebus(i).ac.valid := !ac_sent(i)
                when(io.corebus(i).ac.ready) {
                    ac_sent(i) := true.B
                }
                
            } .otherwise {
                // For requester host do not send snoop request
                ac_sent(i) := true.B
            }

            when(ac_sent.asUInt().andR) {
                    state := STATE_WRITE_INVALIDATE_RESP
                }
            
        } .elsewhen (state === STATE_WRITE_INVALIDATE_RESP) {
            // TODO: Wait for all responses
            // Then porcess them
            cr_done(current_active_num) := true.B
            when(cr(i).valid) {
                cr(i).ready := true.B
                chisel3.assert(cr(i).bits.resp(0), "!ERROR! Interconnect: Snoop response unexpected data transfer")
                chisel3.assert(cr(i).bits.resp(1), "!ERROR! Interconnect: Snoop response unexpected ecc error")
                chisel3.assert(cr(i).bits.resp(2), "!ERROR! Interconnect: Snoop response unexpected dirty")
                cr_done(i) := true.B
            }
            when(cr_done.asUInt().andR) {
                state := STATE_WRITE_ADDRESS
            }
            // TODO: When all responses are done jump to write address state
        } .elsewhen (state === STATE_WRITE_ADDRESS) {
            // afterwards 
            mbus.aw.valid := true.B
            
            when(mbus.aw.ready) {
                state := STATE_WRITE_DATA
            }
            aw(current_active_num).ready := mbus.aw.ready
            chisel3.assert(aw(current_active_num).valid) // Assert that valid is asserted
            // It's AXI violation to de assert it
        } .elsewhen (state === STATE_WRITE_DATA) {
            mbus.w.valid := w(current_active_num).valid
            w(current_active_num).ready := mbus.w.ready

            when(w(current_active_num).valid &&
                w(current_active_num).ready &&
                w(current_active_num).bits.last) {
                    // Last transaction
                    state := STATE_WRITE_RESPONSE
            }
        } .elsewhen (state === STATE_WRITE_RESPONSE) {
            io.corebus(current_active_num).b.valid := mbus.b.valid
            mbus.b.ready := io.corebus(current_active_num).b.ready
            when(mbus.b.valid && mbus.b.ready) {
                state := STATE_WRITE_WACK
            }
        } .elsewhen (state === STATE_WRITE_WACK) {
            when(io.corebus(current_active_num).wack) {
                state := STATE_IDLE
            }
        } .elsewhen (state === STATE_READ_POLL) {
            // Send polls to caches
            io.corebus(i).ac.bits.addr := ar(current_active_num).bits.addr
            io.corebus(i).ac.bits.snoop := "b0001".U // ReadShared, TODO: Maybe ReadClean is better?
            io.corebus(i).ac.bits.prot := aw(current_active_num).bits.prot
            when(current_active_num =/= i.U) {
                io.corebus(i).ac.valid := !ac_sent(i)
            } .otherwise {
                ac_sent(i) := true.B // For active one no need to poll it
            }
            when(io.corebus(i).ac.ready) {
                ac_sent(i) := true.B
            }
            when(ac_sent.asUInt().andR) {
                state := STATE_READ_RETURN_RESPONSE
            }
            // TODO: Test it
        } .elsewhen (state === STATE_READ_RETURN_RESPONSE) {
            when(current_active_num =/= i.U) {
                // Wait for responses
                when(cr(i).valid) {
                    cr_done(i) := true.B
                    cr(i).ready := true.B
                    data_available := data_available | cr(i).bits.resp(0)
                    chisel3.assert(!cr(i).bits.resp(1), "!ERROR! Interconnect: Read request ECC error not supported") // ECC is not supported
                    chisel3.assert(!cr(i).bits.resp(2), "!ERROR! Interconnect: Read request snoop response dirty bit set") // Dirty is not supported
                    data_available_host(i) := cr(i).bits.resp(0)
                }
            } .otherwise {
                cr_done(i) := true.B // For active one no need to wait for response
            }

            when(cr_done.asUInt().andR) {
                when(data_available) {
                    state := STATE_READ_RETURN_DATA
                } .otherwise {
                    state := STATE_READ_ADDRESS
                }
            }
            
            // If any responses have Return Data set then go to return data
            // Else go to STATE_READ_ADDRESS
            
            // TODO: 
        } .elsewhen (state === STATE_READ_RETURN_DATA) {
            // If any data is valid and no selection wad done, select it
            // Cases for hosts:

            
            
            // Unselected no data
            // Unselected data
            // Selected data
            // 1. Requester is not requested so cd(i).valid cant be set for requester
            
            // 2. No selection
            when(cd(i).valid && !return_host_select_valid) { // MSB highest priority to LSB lowest
                return_host_select := i.U
                return_host_select_valid := true.B
            }
            // Selected
            when(return_host_select_valid) {
                // Unselected hosts, no data, nothing to do
                // For requester data_available_host === 0, so this is also case for requester host
                when(!data_available_host(i)) {
                    cd_done(i) := true.B
                }
                
                when(data_available_host(i)) {
                    // Unselected hosts, data
                    when(return_host_select =/= i.U) {
                        cd(i).ready := true.B
                        when(cd(i).valid && cd(i).ready && cd(i).bits.last) {
                            cd_done(i) := true.B
                        }
                    }

                    // Selected host
                    when(return_host_select === i.U) {
                        when(cd(i).valid && cd(i).ready && cd(i).bits.last) {
                            cd_done(i) := true.B
                        }
                        io.corebus(current_active_num).r.valid := cd(return_host_select).valid
                        cd(return_host_select).ready := io.corebus(current_active_num).r.ready
                    }
                }
                

                // All memories done
                when(cd_done.asUInt().andR) {
                    state := STATE_READ_RACK
                }
            }
            

            io.corebus(i).r.bits.resp := "b1000".U // Shared not dirty and available
            io.corebus(i).r.bits.id   := rid
            io.corebus(i).r.bits.data := cd(return_host_select).bits.data
            io.corebus(i).r.bits.last := cd(return_host_select).bits.last
            
        } .elsewhen (state === STATE_READ_ADDRESS) {
            // afterwards 
            mbus.ar.valid := true.B
            
            when(mbus.ar.ready) {
                state := STATE_READ_RESPONSE
            }
            ar(current_active_num).ready := mbus.ar.ready
            chisel3.assert(ar(current_active_num).valid) // Assert that valid is asserted
            // TODO:
        } .elsewhen (state === STATE_READ_RESPONSE) {
            assert(io.corebus(i).r.bits.id === rid)


            io.corebus(i).r.bits := io.mbus.r.bits


            io.mbus.r.ready := io.corebus(current_active_num).r.ready
            io.corebus(current_active_num).r.valid := io.mbus.r.valid

            when(io.corebus(current_active_num).r.valid && io.corebus(current_active_num).r.ready && io.corebus(current_active_num).r.bits.last) {
                state := STATE_READ_RACK
            }
        } .elsewhen (state === STATE_READ_RACK) {
            when(io.corebus(current_active_num).rack) {
                state := STATE_IDLE
            }
            // TODO: 
        } .otherwise {
            printf("!ERROR! Interconnect: Invalid state")
        }
    }
}