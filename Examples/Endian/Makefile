ifndef BDPIPIPE
	BDPIPIPE=/home/jcassidy/src
endif

ifndef BOOST_INCLUDE
	BOOST_INCLUDE=/usr/local/include
endif

ifndef CAPI_CXL_DIR
	CAPI_CXL_DIR=/home/jcassidy/src/CAPI/pslse/libcxl
endif

BSC_OPTS=-p +:../..:../../Core:../../MMIO:../../DedicatedAFU:$(BDPIPIPE) -check-assert -aggressive-conditions
BSC_VER_OPTS=$(BSC_OPTS) -opt-undetermined-vals -unspecified-to X

MODNAME=Endian

default: test-$(MODNAME)

mkSyn_%.v: %.bsv
	bsc -verilog -u $(BSC_OPTS) $<
	bsc -verilog $(BSC_VER_OPTS) -g mkSyn_$* $<

%: %.cpp
	g++ -g -std=c++11 -m64 -fPIC -L$(CAPI_CXL_DIR) -I$(CAPI_CXL_DIR) -I$(BLUELINK) $(LINUX_PROXY) -I$(BDPIPIPE) -I$(BOOST_INCLUDE) $(HARDWARE_DEF) -o $@ $< -lcxl -lpthread -lgmp

test-%: % mkSyn_%.v work
	xterm -hold -e "sleep 6; cd /home/jcassidy/src/CAPI/pslse/pslse; ./pslse"&
	xterm -hold -e "sleep 8; ./$*"&
	vsim -do "source test_$*.tcl" -c
	
work:
	vlib work
	vmap bsvlibs ../../bsvlibs
	vmap vsim_bluelink ../../vsim_bluelink
	ln -s ../../capi_*.tcl .
	ln -s ../../pslse_server.dat

clean:
	rm -rf work $(MODNAME) mkSyn_*.v *.b[ao] modelsim.ini transcript pslse_server.dat capi_*.tcl *.wlf
