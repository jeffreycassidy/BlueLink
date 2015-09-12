BDPIPIPE=/home/jcassidy/src/BDPIPipe

BSC_OPTS=-p +:../..:../../Core:../../MMIO:../../DedicatedAFU:$(BDPIPIPE) -check-assert -aggressive-conditions
BSC_VER_OPTS=$(BSC_OPTS) -opt-undetermined-vals -unspecified-to X

default: test-Memcopy2

mkSyn_Memcopy2.v: Memcopy2.bsv
	bsc -verilog -u $(BSC_OPTS) $<
	bsc -verilog $(BSC_VER_OPTS) -g mkSyn_Memcopy2 $<

Memcopy2: Memcopy2.cpp
	g++ -g -std=c++11 -m64 -fPIC -L$(PSLSE_CXL_DIR) -I$(PSLSE_CXL_DIR) -I$(BLUELINK) $(HARDWARE_DEF) -o $@ $< -lcxl -lpthread

test-Memcopy2: Memcopy2 mkSyn_Memcopy2.v work
	xterm -hold -e "sleep 6; cd /home/jcassidy/src/CAPI/pslse/pslse; ./pslse"&
	xterm -hold -e "sleep 8; ./Memcopy2"&
	vsim -do "source test_Memcopy2.tcl"
	
work:
	vlib work
	vmap bsvlibs ../../bsvlibs
	vmap vsim_bluelink ../../vsim_bluelink
	ln -s ../../capi_*.tcl .
	ln -s ../../pslse_server.dat

clean:
	rm -rf work Memcopy2 mkSyn_Memcopy2.v *.b[ao] modelsim.ini transcript pslse_server.dat capi_*.tcl *.wlf
