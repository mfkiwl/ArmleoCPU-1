package armleocpu

import chisel3.stage.{ChiselGeneratorAnnotation, ChiselStage}



object ArmleoCPUDriver extends App {
  //(new ChiselStage).emitVerilog(new ArmleoCPU)
}


object ALUDriver extends App {
  (new ChiselStage).execute(args, Seq(ChiselGeneratorAnnotation(() => new ALU)))
}

object RegfileDriver extends App {
  (new ChiselStage).execute(args, Seq(ChiselGeneratorAnnotation(() => new Regfile)))
}

object CacheBackstorageDriver extends App {
  (new ChiselStage).execute(Array("-frsq", "-c:CacheBackstorage:-o:generated_vlog/cache_backstorage_mems.conf","--target-dir", "generated_vlog"), Seq(ChiselGeneratorAnnotation(() => new CacheBackstorage(new CacheParams(arg_tag_width = 64 - 12, arg_ways = 4, arg_lane_width = 3)))))
}


object sram_1rw_Driver extends App {
  (new ChiselStage).execute(Array("-frsq", "-m:sram_1rw;-o:generated_vlog/sram_1rw_mems","--target-dir", "generated_vlog"), Seq(ChiselGeneratorAnnotation(() => new sram_1rw(depth_arg = 1 << 10, data_width = 32, mask_width = 4))))
}