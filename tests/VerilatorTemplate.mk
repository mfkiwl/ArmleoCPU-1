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

# inputs $(top), $(defines) $(files), $(cpp_files)

VERILATOR = verilator
VERILATOR_COVERAGE = verilator_coverage

RANDOM_SEED?=1
VERILATOR_FLAGS = $(verilator_options) -Wall -Wno-UNOPTFLAT -cc --exe $(defines) --trace  -Wno-UNOPTFLAT --coverage $(includepathsI) --top-module $(top)
# VERILATOR_FLAGS += -Wall
verilator_cflags=-CFLAGS "-std=gnu++20 -Wall -Og -DTOP=$(top) -DRANDOM_SEED=$(RANDOM_SEED) -I$(PROJECT_DIR)/tests/"
verilator_cflags_debug=-CFLAGS "-ggdb -std=gnu++20 -Wall -Og -DTOP=$(top) -DRANDOM_SEED=$(RANDOM_SEED) -I$(PROJECT_DIR)/tests/"
VERILATOR_FLAGS_DEBUG = $(VERILATOR_FLAGS) $(verilator_cflags_debug)
VERILATOR_FLAGS += $(verilator_cflags)
VERILATOR_INPUT = $(files) $(cpp_files)

build-verilator: docker_check $(files) $(cpp_files) $(includefiles) $(makefiles)
	$(VERILATOR) $(VERILATOR_FLAGS) $(VERILATOR_INPUT) 2>&1 | tee verilator.log
	! grep "%Error" verilator.log
	
	$(MAKE) -C obj_dir/ OPT_FAST="" -j$(shell nproc) -f V$(top).mk 2>&1 | tee make.log
	! grep "error:" make.log


debugbuild-verilator: docker_check $(files) $(cpp_files) $(includefiles) $(makefiles)
	$(VERILATOR) $(VERILATOR_FLAGS_DEBUG) $(VERILATOR_INPUT) 2>&1 | tee verilator.log
	! grep "%Error" verilator.log
	$(MAKE) -C obj_dir/ OPT_FAST="" -j$(shell nproc) -f V$(top).mk 2>&1 | tee make.log
	! grep "error:" make.log

test-verilator: build-verilator 
	rm -rf logs
	mkdir -p logs
	obj_dir/V$(top) +trace 2>&1 | tee run.log
	! grep "%Error" run.log

	rm -rf logs/annotated
	$(VERILATOR_COVERAGE) --annotate logs/annotated logs/coverage.dat


debug-verilator: debugbuild-verilator
	rm -rf logs
	mkdir -p logs
	gdb obj_dir/V$(top) +trace

	@echo "Coverage not generated because running in debug mode"
# rm -rf logs/annotated
# $(VERILATOR_COVERAGE) --annotate logs/annotated logs/coverage.dat


lint-verilator: docker_check $(files) $(cpp_files) $(includefiles) $(makefiles)
	$(VERILATOR) --lint-only -Wall -Wno-UNOPTFLAT $(verilator_options) $(includepathsI) --top-module $(top) $(files) 2>&1 | tee verilator.lint.log
	! grep "%Error" verilator.lint.log

clean-verilator: docker_check
	rm -rf *.log logs *.vcd obj_dir

include $(PROJECT_DIR)/files.mk
include $(PROJECT_DIR)/dockercheck.mk
