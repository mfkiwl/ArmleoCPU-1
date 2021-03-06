###############################################################################
# 
# This file is part of ArmleoCPU.
# ArmleoCPU is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
# 
# ArmleoCPU is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with ArmleoCPU.  If not, see <https:#www.gnu.org/licenses/>.
# 
# Copyright (C) 2016-2021, Arman Avetisyan, see COPYING file or LICENSE file
# SPDX-License-Identifier: GPL-3.0-or-later
# 
###############################################################################

top?=top
top_tb?=$(top)_tb

synth.yosys.temp.tcl: docker_check Makefile $(PROJECT_DIR)/tests/YosysTemplate.mk
	rm -rf synth.yosys.temp.tcl
	echo "yosys -import" >> synth.yosys.temp.tcl
	echo "verilog_defaults -add $(includepathsI)" >> synth.yosys.temp.tcl
	for file in $(files); do echo "read_verilog -sv $${file}" >> synth.yosys.temp.tcl; done

	echo "synth_intel -family cycloneiv -top $(top) -vqm synth_quartus.yosys.temp.v" >> synth.yosys.temp.tcl
	echo "clean" >> synth.yosys.temp.tcl
	echo "write_verilog synth.yosys.temp.v" >> synth.yosys.temp.tcl
synth-yosys: docker_check synth.yosys.temp.tcl
	yosys -c synth.yosys.temp.tcl 2>&1 | tee yosys.log
	! grep "ERROR:" yosys.log
	! grep "\$$_DLATCH_" yosys.log

clean-synth-yosys:
	rm -rf abc.history synth.yosys.temp.tcl yosys.log synth.yosys.temp.v synth_quartus.yosys.temp.v


# CXXRTL

synth_cxxrtl.yosys.temp.tcl: docker_check Makefile $(PROJECT_DIR)/tests/YosysTemplate.mk
	rm -rf synth_cxxrtl.yosys.temp.tcl
	echo "yosys -import" >> synth_cxxrtl.yosys.temp.tcl
	echo "verilog_defaults -add $(includepathsI)" >> synth_cxxrtl.yosys.temp.tcl
	for file in $(files); do echo "read_verilog -sv $${file}" >> synth_cxxrtl.yosys.temp.tcl; done
	echo "write_cxxrtl synth_cxxrtl.yosys.temp.cpp" >> synth_cxxrtl.yosys.temp.tcl

synth-yosys-cxxrtl: synth_cxxrtl.yosys.temp.tcl
	yosys -c synth_cxxrtl.yosys.temp.tcl 2>&1 | tee yosys_cxxrtl.log
	! grep "ERROR:" yosys_cxxrtl.log
	! grep "\$$_DLATCH_" yosys_cxxrtl.log

clean-yosys-cxxrtl:
	rm -rf abc.history synth_cxxrtl.yosys.temp.tcl yosys_cxxrtl.log synth_cxxrtl.yosys.temp.cpp

clean-yosys: docker_check clean-synth-yosys clean-yosys-cxxrtl
	
include $(PROJECT_DIR)/files.mk
include $(PROJECT_DIR)/dockercheck.mk
