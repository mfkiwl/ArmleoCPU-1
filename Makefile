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

all: docker_check clean test

test: check docker_check
	$(MAKE) -C $(PROJECT_DIR)/tests test

cloc.log: docker_check
	cloc $(PROJECT_DIR) > cloc.log

clean: docker_check
	rm -rf check.log
	$(MAKE) -C $(PROJECT_DIR)/tests clean
	rm -rf cloc.log

check: docker_check
	$(MAKE) --version > check.log

include docker.mk
include dockercheck.mk
