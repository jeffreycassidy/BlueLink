ifndef BLUELOGIC
    BLUELOGIC=../../../BlueLogic
endif

ifndef BLUELINK
	BLUELINK=../..
endif

BLUESPEC_PATH=+:$(BLUELOGIC)/Pipeline:$(BLUELINK)/Core:$(BLUELOGIC)/Convenience:$(BLUELINK)/TagManager

ifndef CAPI_CXL_DIR
	CAPI_CXL_DIR=/home/jcassidy/src/CAPI/pslse/pslse
endif

default: mkMemcopyTB.v

ibm: 
#	scp Makefile WED.?pp AFU.?pp ~/src/CAPI/CAPI_DOCS/PSL\ Release\ Revision\ 0/psl_A000_0000_1/quartus_output/psl.rbf ubuntu@stac.aus.stglabs.ibm.com:/home/ubuntu/jcassidy/memcopy
	rsync -crizt --progress Makefile WED.?pp AFU.?pp host_memcopy.?pp ~/src/CAPI/CAPI_DOCS/PSL\ Release\ Revision\ 0/psl_A000_0000_1/quartus_output/psl.rbf ubuntu@stac.aus.stglabs.ibm.com:/home/ubuntu/jcassidy/memcopy

host_memcopy: host_memcopy.cpp AFU.hpp WED.hpp
	g++ -Wall -g -fPIC -std=c++11 $(HARDWARE) -I$(CAPI_CXL_DIR) -L$(CAPI_CXL_DIR) -o $@ $< $(CAPI_CXL_DIR)/libcxl.a -lpthread
	
remote:
	ssh parallels@10.211.55.6 "make -C /home/jcassidy/src/BlueLink/Examples/Memcopy host_memcopy" 

# make the Verilog target
mkMemcopyTB.v: Test_Memcopy.bsv Memcopy.bsv
	bsc -check-assert -p $(BLUESPEC_PATH) -u $<
	bsc -check-assert -p $(BLUESPEC_PATH) -verilog -g mkMemcopyTB $<

mkMemcopyAFU.v: Memcopy.bsv
	bsc -check-assert -p $(BLUESPEC_PATH) -u $<
	bsc -check-assert -p $(BLUESPEC_PATH) -verilog -g mkMemcopyAFU $<

endian: Test_Endianness.bsv Endianness.bsv
	bsc -check-assert -u $<
	bsc -check-assert -sim -g mkEndianTest $<
	bsc -check-assert -sim -e mkEndianTest -o $@

clean:
	rm -f *.o *.so schedule.* transcript vsim.wlf wlft* *.cxx mk*.c mk*.h pseries_nvram.* *.ba *.bo mkMemcopyTB.v
