BSC_OPTS=-check-assert -p +:MMIO:DedicatedAFU:Core:../BDPIPipe:../FullMonte/modules:../FullMonte/modules/ReflectRefract -aggressive-conditions

BSC_SIM_OPTS=$(BSC_OPTS) -sim
BSC_VER_OPTS=$(BSC_OPTS) -verilog -opt-undetermined-vals -unspecified-to X

SUBDIRS=Core DedicatedAFU MMIO

test-ResourceManager: ResourceManager.bsv
	bsc $(BSC_SIM_OPTS) $<
	bsc $(BSC_SIM_OPTS) -g mkTB_ResourceManager $<
	bsc $(BSC_SIM_OPTS) -e mkTB_ResourceManager -o $@

test-afu2host: work bsvlibs libs afu2host mkSyn_AFUToHost.v
	vsim -do "source test_afu2host.tcl"

test-host2afu: work bsvlibs libs host2afu mkSyn_HostToAFU.v
	vsim -do "source test_host2afu.tcl"

test-refrefhost: work bsvlibs libs refrefhoststream mkSyn_RefRefHost.v
	vsim -do "source test_refrefhost.tcl"

mkSyn_AFUToHost.v: AFUToHostStream.bsv ReadBuf.bsv 
	bsc $(BSC_VER_OPTS) -u $<
	bsc $(BSC_VER_OPTS) -g mkSyn_AFUToHost -o $@ $<

mkSyn_HostToAFU.v: Test_HostToAFUStream.bsv ReadBuf.bsv HostToAFUStream.bsv
	bsc $(BSC_VER_OPTS) -u $<
	bsc $(BSC_VER_OPTS) -g mkSyn_HostToAFU -o $@ $<

mkSyn_RefRefHost.v: Test_RefRefHostStream.bsv ReadBuf.bsv AFUToHostStream.bsv HostToAFUStream.bsv
	bsc $(BSC_VER_OPTS) -u $<
	bsc $(BSC_VER_OPTS) -g mkSyn_RefRefHost -o $@ $<

afu2host: afu2host.cpp
	g++ -g -std=c++11 -m64 -fPIC -L$(PSLSE_CXL_DIR) -I$(PSLSE_CXL_DIR) -I$(BLUELINK) -o $@ $< -lcxl -lpthread

host2afu: host2afu.cpp *.hpp
	g++ -g -std=c++11 -m64 -fPIC -L$(PSLSE_CXL_DIR) -I$(PSLSE_CXL_DIR) -I$(BLUELINK) -o $@ $< -lcxl -lpthread

refrefhoststream: refrefhoststream.cpp
	g++ -g -std=c++11 -m64 -fPIC -L$(PSLSE_CXL_DIR) -I$(PSLSE_CXL_DIR) -I$(BLUELINK) -I../BDPIPipe -o $@ $< -lcxl -lpthread -lgmp

clean:
	for i in $(SUBDIRS); do make -C $$i clean; done
	rm -rf *.so bsvlibs afu2host host2afu *.b[ao] model_*.cxx model_*.cxx mk*.v vpi_wrapper_*.[ch] work *.o mk*.cxx mk*.h model_*.h \
		register.c *.vstf transcript *.wlf *.dSYM  *.out build.log

test-CmdBuf: mkTB_CmdBuf.v work
	vsim -c -do "vlog mkTB_CmdBuf.v; vsim -L bsvlibs -L altera_mf_ver mkTB_CmdBuf; force CLK -drive 1'b0, 1'b1 5 -repeat 10; force RST_N -drive 1'b0, 1'b1 10; run -all;"


mkTB_CmdBuf.v: Test_CmdBuf.bsv CmdBuf.bsv
	bsc $(BSC_VER_OPTS) -u $<
	bsc $(BSC_VER_OPTS) -g mkTB_CmdBuf $<

CmdBuf.bo: CmdBuf.bsv
	bsc $(BSC_VER_OPTS) -u $<

work:
	vlib work
	vlog -timescale 1ns/1ns MLAB_0l.v

# compile all of the Bluespec libraries into their own Modelsim lib
bsvlibs:
	vlib bsvlibs
	vlog -work bsvlibs -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+TOP="foo" +define +BSV_ASSIGNMENT_DELAY=\#1 $(BLUESPECDIR)/Verilog/*.v

libs:
	for i in $(SUBDIRS); do make -C $$i libs; done
