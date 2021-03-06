This file is part of ArmleoCPU.
ArmleoCPU is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

ArmleoCPU is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with ArmleoCPU.  If not, see <https://www.gnu.org/licenses/>.

Copyright (C) 2016-2021, Arman Avetisyan, see COPYING file or LICENSE file
SPDX-License-Identifier: GPL-3.0-or-later

# Contribution
Install docker and clone repository somewhere. Then execute following to enter docker with preinstalled toolset:
```
make interactive
```

`src/` contains all of the source code of modules. `tests/` contains test groups. `tests/submodule_tests/` contains individual tests. You can take a look at all tests and use it as a reference for your tests.

Currently we support two "simulators": Verilator and Icarus Verilog. All code is assumed to be synthesizable with Yosys, Veilator and Icarus Verilog.

Running make in each submodule tests directory will usually run Icarus Verilog simulation, yosys synthesis and Verilator linting and simulation. Optionally one of Verilator simulation or Icarus Verilog can be disabled.

Note: If files other than verilog files are changed full clean is required because Makefiles ignore files that is not directly in the list of verilog files
Note: If any include/template files are modified full clean is required to make sure all tests are done with new include files


For high level modules it is required to implement a Verilator testbench because Verilator can also generate coverage reports. Use this information and your knowledge to decide if your tests are done or not.

You can find a lot of documentation about RISC-V on their official website. For this project we use Privileged spec and ISA Spec. Later exact versions will be posted to make sure that all RTL follows same documentation.

You may also need to take a look at RISC-V PLIC, ACLINT, and maybe even AXI4 documentation for relevant modules.

## How to help?
You can take a look at README.md and see current features that are not implemented and start working on them. You may create and Issue on GitHub and request what exactly needs to be done for that feature. I will respond and will provide more details.

There is also some Issues marked "good first issue". Comment there and I will provide more details.

## Disallowed words
It is disallowed to use words m#ster and sl#ve. Use host/client or host/device. For words bl#ck list and wh#ite list use disallowed and allowedlist. Ban of this words are not discussed.

## License
Each file includes a GPLv3 header and copyright. Note that all contribution to this repository require you to transfer ownership of your code to Arman Avetisyan. This requirement is done, because source code is dual-licensed under proprietary license. It also limits our ability to use GPL code in this project.


# Module documentation:

## Memory cells that you may replace
This project uses three memory cells: mem_1rwm (1 address read write masked) and mem_1rw (1 address read write) and regfile_one_lane (1 address write, 1 address read).

If you want to use alternative 1 address write, 2 address read architecture for register file, you can replace regfile.sv.

Keep in mind that there is requirements to all of these memory:
* After read, value that was fetches from memory stays the same until next read request, even if write was done to same location.
* Read result is provided on next cycle of request.
* Write is done in same cycle and is read-first, in other words writing and reading to same locaiton in same cycle results in readdata containing value that was before the location was written.

## Cache
!IMPORTANT! Cachable region should be all read AND writable or return error if address does not exist for both read AND write requests.  
!IMPORTANT! Cachable region must be 64 byte aligned.  
!IMPORTANT! Cachable region should return error on first cycle of read burst.  

Cache is multiple way multi set physically tagged with two cycle latency on hit.
It reads from storage at index address idx and in first cycle and requests tlb address resolve.
On second cycle it compares all tags and tlb physical address and outputs data or generates a stall in case of miss or tlb miss.

It is not recommended to allow multiple memory mapping of same region or device in the memory, as this will cause cache to duplicate cached data and cause core to read outdated values if data is read thru different region, as old region will contain invalid data.

Note: AWPROT and ARPROT signals contain information about current privilege levels, allowing to make some memory (like machine mode software memory) is invisible to other privilege levels.

Note: Current waveforms and images of internal structure of Cache are outdated, somebody really needs to fix this :D.


# Atomic operations
Cache implements load-reserve and store-conditional operations, while execute unit uses this to implement AMO operations.

Note that atomic operations are passed to AXI4 interface. This means that all memory devices connected to AXI4 have to support atomic access.

"armleocpu_axi_exclusive_monitor" can be used in front of AXI4 memory/peripheral modules that do not support it. Keep in mind that it is required to put this module BEFORE it reaches the endpoint. This is because not all peripheral devices are supposed to support atomic access. See example
```
CPU <-> Crossbar <-> exclusive monitor <-> ddr controller
                 <-> ACLINT that DOES NOT SUPPORT exclusive access and it is intentionally done so
                 <-> PLIC that DOES NOT SUPPORT exclusive access and it is intentionally done so
                 <-> some other peripheral that DOES NOT SUPPORT exclusive access and it is intentionally done so to met some specifications or standarts.
```
# PTW
See source code. It's implementation of RISC-V Page table walker that generated pagefault for some cases and returns access bits with resolved physical address 
It always gives 4K Pages, because this is what Cache was designed for.


# Fetch
TODO: Add protocol description


# Privileges

## CSR registers

|Done   |Test   |Feature             |
|:-----:|:-----:|:------------------:|
|Y      |Y      |machine_info_regs   |
|Y      |Y      |misa                |
|Y      |Y      |mstatus/tvm_tw_tsr  |
|Y      |Y      |mstatus/mxr_mprv_sum|
|Y      |Y      |mtvec               |
|Y      |Y      |mscratch            |
|Y      |Y      |sscratch            |
|Y      |Y      |mepc                |
|Y      |Y      |mcause              |
|Y      |Y      |mtval               |
|Y      |Y      |mcycle/mcycleh      |
|Y      |Y      |minstret/minstret   |
|Y      |Y      |stvec               |
|Y      |Y      |sepc                |
|Y      |Y      |scause              |
|Y      |Y      |stval               |
|Y      |Y      |satp                |
|Y      |Y      |medeleg             |
|Y      |Y      |mideleg             |
|Y      |Y      |mie                 |
|Y      |Y      |sie                 |
|Y      |Y      |sstatus             |
|Y      |Y      |mip                 |
|Y      |Y      |sip                 |
|N      |N      |interrupt_begin     |
|N      |N      |exception_begin     |
|N      |N      |mret                |
|N      |N      |sret                |
|Y      |N      |READ_SET, READ_CLEAR|
|N      |N      |mcounteren          |
|N      |N      |scounteren          |
|N      |N      |supervisor_timers   |
|N      |N      |user_timers         |


Interrupt handling:
If machine mode and mstatus.mie is 1 and respective bit in mie is 1, then Machine mode handles the interrupt
else if supervisor mode 
    if respective bit in mie is 1 then Machine handles the interrupt

Note: All interrupts and exceptions are handled by machine mode software, and redirected to supervisor software when required.

User CSR are not implemented, because we don't support user interrupts

We don't support floating points, so floating point CSR are not implemented

We don't support user interrupts, so sedeleg and sideleg is not implemented

satp is implemented and SV32 (34 bit physical addressing) is supported  

mvendorid, marchid, mimpid, mhartid is implemented as read-only registers parametrized from top

Only direct interrupt/exception mode is supported for mtvec/stvec
mtval is implemented but reads always zero   
mstatus bits:  
* FS and XS is hardwired to zero because no Floating point is implemented  
* SD is hardwired to zero because FS and XS is hardwired to zero  


# interrupts
When interrupt happens, CPU copies current pc to epc.
Privilege is set to machine and previous privilege is set old value of privilege
interrupt pending for that interrupt goes high
interrupt enable for that interrupt goes low
interrupt pending should be cleared and interrupt enabled should be high, when cpu `mret`s to user code.

* Timer interrupt
External interrupt
Illegal instruction
Page fault
Memory Access Fault
ECALL
EBREAK
Fetch Address missaligned
Load/Store Address missaligned


# Memory managment
SFENCE.VMA, FENCE and FENCE.I are equivalent and flush ICACHE,DCACHE, ITLB and DTLB for local core.

Memory is weak ordered, but might become strict ordered with small changes forcing cache to invalidate its data when write is done by any core. This has significant perfomance hit, but it will take too long to implement proper cache coherency.

# CLINT, CLIC, PLIC
CLINT is a core local interrupter as defined by RISC-V Specification.
Memory map is compatible witth spike: https://github.com/riscv/riscv-isa-sim/blob/master/riscv/clint.cc

CLIC is proposed faster, core local interrupt controller.

PLIC is what connects external interrupts sources like UART, SPI, etc to many cores. PLIC has a lot of features that is important on multi core systems. For single core sytems this can be replaced with singular wide or of all interrupt sources and small bootloader update.

Specificaiton can be found here: https://github.com/riscv/riscv-plic-spec/blob/master/riscv-plic.adoc

# Booting Linux
Currently this core does not support booting Linux, but when it does a documentation like below will be specified.

https://qemu-project.gitlab.io/qemu/system/riscv/sifive_u.html

# DEBUG
Status: Not implemented yet

Debug module allows to debug CPU from first cycle executed. To do this special signal is implemented.
If this signal is set then after reset debug module will enter active debug mode.

When debug_req is hold high debug_ack will go high after some cycles
and CPU will enter debug mode and debug_mode will go high.
When debug_exit_request goes high, debug_ack will go high after some cycles and cpu will exit debug mode.
When in debug mode CPU is stopped.
Each command must be written to debug0.
Commands:
```
    DEBUG_RESET = 1
    DEBUG_SET_PC = 2
    DEBUG_GET_PC = 3
    DEBUG_SET_REG = 4
    DEBUG_GET_REG = 5
    DEBUG_WRITE_MEMORY = 6
    DEBUG_READ_MEMORY = 7
    DEBUG_LOAD_RESERVE = 8
    DEBUG_STORE_CONDITIONAL = 9
    DEBUG_SET_CSR = 10
    DEBUG_GET_CSR = 11
    DEBUG_FLUSH = 12
```
RESET resets whole cpu and outputs reset signal to peripheral
SET_PC sets PC to value of debug1
GET_PC gets PC and places value to debug1
SET_REG sets register number debug1 to value of debug2
GET_REG gets register number debug1 and places into debug2
WRITE_MEMORY writes data to memory with MMU enabled. debug1 is address and debug2 is value to write
READ_MEMORY reads data from memory with MMU enabled. debug1 is address and debug2 is value that was read
SET_CSR sets number debug1 csr with value debug2
GET_CSR gets number debug1 csr and places into debug2
FLUSH flushes cache and tlb

You need to write debug1 and debug2 and then set debug0 with command.
    when debug0 goes to 255 that means that command is executed and debug1 or debug2 holds correct value

To write to or read from physical address you need to execute
    GET CSR from satp,
    SET_CSR to satp with disabled mmu,
    FLUSH the cache and tlb,
    execute WRITE_MEMORY or READ_MEMORY,
    SET_CSR with old value of msatp,
    FLUSH the cache and tlb,
There is no hardware breakpoints, so to place breakpoint you need to place EBREAK into instruction stream for Machine code.
If code is user space then machine mode kernel should handle debug commands using separate interface or same interface. Because debug0,1,2 is ignored when not in debug mode.

# Other documentation
Note: That currently all documentation is outdated, when project will be prepared with release this will contain all information required to go from FPGA to fully featured SoC and even will contain information about extending the CPU

