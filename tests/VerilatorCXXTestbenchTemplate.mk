
test: test-verilator lint-verilator
debug: lint-verilator debug-verilator
clean: clean-verilator

include $(PROJECT_DIR)/files.mk
include $(PROJECT_DIR)/tests/VerilatorTemplate.mk