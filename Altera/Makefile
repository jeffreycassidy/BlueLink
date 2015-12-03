BSC_OPTS=-check-assert -aggressive-conditions -p +:/home/parallels/src/FMHW/modules

BSC_SIM_OPTS=$(BSC_OPTS) -sim
BSC_VER_OPTS=$(BSC_OPTS) -verilog -opt-undetermined-vals -unspecified-to X

mkTest_M20kPipe.v: Test_AlteraM20k.bsv
	bsc $(BSC_VER_OPTS) -u $<
	bsc $(BSC_VER_OPTS) -g mkTest_M20kPipe $<

MemTest: MemTest.cpp
	g++ -std=c++11 -O3 -Wall -fPIC -o $@ $^

test-M20kPipe: work mkTest_M20kPipe.v MemTest
	vlog '+define+BSV_ASSIGNMENT_DELAY=#1' -timescale 1ns/1ps BRAM2.Stall.v BRAM2.Fixed.v mkTest_M20kPipe.v $(BLUESPECDIR)/Verilog/FIFOL10.v
	vsim -c -do "vsim -t 1ns -L altera_mf_ver mkTest_M20kPipe; force -drive CLK 1'b0, 1'b1 @ 2 -repeat 4; force -drive RST_N 1'b0, 1'b1 @ 8; run -all"


mkTB_MemScanChainElement_%.v: Test_MemScanChain.bsv
	bsc $(BSC_VER_OPTS) -u $<
	bsc $(BSC_VER_OPTS) -g mkTB_MemScanChainElement_$* $<

mkSyn_MemScanChain.v: Test_MemScanChain.bsv
	bsc $(BSC_VER_OPTS) -u $<
	bsc $(BSC_VER_OPTS) -g mkSyn_MemScanChain $<


test-%: work mkTB_%.v
	vlog '+define+BSV_ASSIGNMENT_DELAY=#1' -timescale 1ns/1ps BRAM2.Stall.v mkTB_$*.v $(BLUESPECDIR)/Verilog/FIFOL10.v $(BLUESPECDIR)/Verilog/FIFO2.v $(BLUESPECDIR)/Verilog/FIFO1.v $(BLUESPECDIR)/Verilog/FIFOL1.v
	vsim -c -do "vsim -t 1ns -L altera_mf_ver mkTB_$*; force -drive CLK 1'b0, 1'b1 @ 2 -repeat 4; force -drive RST_N 1'b0, 1'b1 @ 8; run -all"

work: 
	vlib work
