test-ResourceManager: ResourceManager.bsv
	bsc $(BSC_SIM_OPTS) $<
	bsc $(BSC_SIM_OPTS) -g mkTB_ResourceManager $<
	bsc $(BSC_SIM_OPTS) -e mkTB_ResourceManager -o $@

mkSyn_HostToAFUBulk.v: Test_HostToAFUBulk.bsv HostToAFUBulk.bsv
	bsc -u $(BSC_VER_OPTS) $<
	bsc $(BSC_VER_OPTS) -g mkSyn_HostToAFUBulk -o $@ $<

test-h2abulk: work bsvlibs vsim_bluelink libs mkSyn_HostToAFUBulk.v
	vsim -do "source test_h2abulk.tcl"&
	xterm -hold -e "sleep 6; pslse"&
	xterm -hold -e "sleep 8; ./host2afu"&

h2abulkreorder: h2abulkreorder.cpp
	g++ -std=c++11 -fPIC -O3 -I/usr/local/include -lgmp -o $@ $^
	

test-afu2host: work bsvlibs vsim_bluelink libs afu2host mkSyn_AFUToHost.v
	xterm -hold -e "sleep 6; cd /home/jcassidy/src/CAPI/pslse/pslse; ./pslse"&

test-afu2host512: work bsvlibs vsim_bluelink libs afu2host mkSyn_AFUToHost512.v
	xterm -hold -e "sleep 6; cd /home/jcassidy/src/CAPI/pslse/pslse; ./pslse"&
	xterm -hold -e "sleep 8; ./afu2host"&
	vsim -do "source test_afu2host512.tcl"&


test-afu2host: work bsvlibs vsim_bluelink libs afu2host mkSyn_AFUToHost.v
	xterm -hold -e "sleep 6; cd /home/jcassidy/src/CAPI/pslse/pslse; ./pslse"&
	xterm -hold -e "sleep 8; ./afu2host"&
	vsim -do "source test_afu2host.tcl"&

test-host2afu: work bsvlibs vsim_bluelink libs host2afu mkSyn_HostToAFU.v
	xterm -hold -e "sleep 6; cd /home/jcassidy/src/CAPI/pslse/pslse; ./pslse"&
	xterm -hold -e "sleep 8; ./host2afu"&
	vsim -do "source test_host2afu.tcl"&

mkSyn_AFUToHost.v: Test_AFUToHostStream.bsv AFUToHostStream.bsv ReadBuf.bsv CAPIStream.bsv
	bsc $(BSC_VER_OPTS) -u $<
	bsc $(BSC_VER_OPTS) -g mkSyn_AFUToHost -o $@ $<
	
mkSyn_AFUToHost512.v: Test_AFUToHostStream512.bsv AFUToHostStream512.bsv ReadBuf.bsv CAPIStream.bsv
	bsc $(BSC_VER_OPTS) -u $<
	bsc $(BSC_VER_OPTS) -g mkSyn_AFUToHost512 -o $@ $<
	

mkSyn_HostToAFU.v: Test_HostToAFUStream.bsv ReadBuf.bsv HostToAFUStream.bsv CAPIStream.bsv
	bsc $(BSC_VER_OPTS) -u $<
	bsc $(BSC_VER_OPTS) -g mkSyn_HostToAFU -o $@ $<
	
afu2host: afu2host.cpp Host/*.hpp
	g++ -g -std=c++11 -m64 -fPIC -L$(PSLSE_CXL_DIR) -I$(PSLSE_CXL_DIR) -I$(BLUELINK) -o $@ $< -lcxl -lpthread

host2afu: host2afu.cpp Host/*.hpp
	g++ -g -std=c++11 -m64 -fPIC -L$(PSLSE_CXL_DIR) -I$(PSLSE_CXL_DIR) -I$(BLUELINK) -o $@ $< -lcxl -lpthread

clean:
	for i in $(SUBDIRS); do make -C $$i clean; done
	rm -rf *.so bsvlibs afu2host host2afu *.b[ao] model_*.cxx model_*.cxx mk*.v vpi_wrapper_*.[ch] work *.o mk*.cxx mk*.h model_*.h \
		register.c *.vstf transcript *.wlf *.dSYM  *.out build.log work vsim_bluelink bsvlibs

vsim_bluelink:
	vlib vsim_bluelink
	vlog -work vsim_bluelink -timescale 1ns/1ps '+define+BSV_ASSIGNMENT_DELAY=#1' Altera/MLAB_0l.v

# compile all of the Bluespec libraries into their own Modelsim lib
bsvlibs:
	vlib bsvlibs
	vlog -work bsvlibs -timescale 1ns/1ps +define+BSV_NO_INITIAL_BLOCKS +define+TOP="foo" +define +BSV_ASSIGNMENT_DELAY=\#1 $(BLUESPECDIR)/Verilog/*.v

remote-sync:
	rsync -rizt Host stac:~/jcassidy/BlueLink
	rsync -rizt --include=Makefile --include=*.?pp Examples/Memcopy2 stac:~/jcassidy/Examples
