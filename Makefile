BSC_OPTS=-check-assert -p +:MMIO:DedicatedAFU:Core:../BDPIPipe

BSC_SIM_OPTS=$(BSC_OPTS) -sim
BSC_VER_OPTS=$(BSC_OPTS) -verilog -opt-undetermined-vals -unspecified-to X

test-afu2host: work bsvlibs afu2host mkSyn_AFUToHost.v

mkSyn_AFUToHost.v: AFUToHostStream.bsv ReadBuf.bsv 
	bsc $(BSC_VER_OPTS) -u $<
	bsc $(BSC_VER_OPTS) -g mkSyn_AFUToHost -o $@ $<

afu2host: afu2host.cpp *.hpp
	g++ -g -std=c++11 -m64 -fPIC -L$(PSLSE_CXL_DIR) -I$(PSLSE_CXL_DIR) -I$(BLUELINK) -o $@ $< -lcxl -lpthread

clean: 
	rm -rf *.so bsvlibs afu2host host2afu *.b[ao] model_*.cxx model_*.cxx mk*.v vpi_wrapper_*.[ch] work *.o mk*.cxx mk*.h model_*.h \
		register.c *.vstf transcript *.wlf *.dSYM  *.out build.log

work:
	vlib work

# compile all of the Bluespec libraries into their own Modelsim lib
bsvlibs:
	vlib bsvlibs
	vlog -work bsvlibs -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+TOP="foo" +define +BSV_ASSIGNMENT_DELAY=\#1 $(BLUESPECDIR)/Verilog/*.v
