BSC_OPTS=-aggressive-conditions -check-assert -p +:/home/parallels/src/BlueLink:/home/parallels/src/BlueLink/Core:/home/parallels/src/BlueLink/DedicatedAFU:/home/parallels/src/BlueLink/MMIO:/home/parallels/src/FMHW/modules:/home/parallels/src/BlueLink/Altera

BSC_VER_OPTS=$(BSC_OPTS) -verilog -opt-undetermined-vals -unspecified-to X

.PRECIOUS: mkSyn_MemLoad.v MemLoadHost

test-MemLoad: mkSyn_MemLoad.v MemLoadHost
	vsim -c -do "source test.tcl"

mkSyn_MemLoad.v: MemLoad.bsv work
	bsc $(BSC_VER_OPTS) -u $<
	bsc $(BSC_VER_OPTS) -g mkSyn_MemLoad $<

MemLoadHost: MemLoadHost.cpp
	g++ -Wall -std=c++11 -O3 -g -I/home/parallels/src -I/home/parallels/src/CAPI/pslse/libcxl $< -o $@ -L/home/parallels/src/CAPI/pslse/libcxl -lpthread -lcxl

work:
	vlib work
