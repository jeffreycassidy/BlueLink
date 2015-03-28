ifndef BLUELOGIC
    BLUELOGIC=../../../BlueLogic
endif

ifndef BLUELINK
	BLUELINK=../..
endif

BLUESPEC_PATH=+:$(BLUELOGIC)/Pipeline:$(BLUELINK)/Core:$(BLUELOGIC)/Convenience
CAPI_PSL_DIR=/home/parallels/src/CAPI

host_memcopy: host_memcopy.cpp
	g++ -Wall -fPIC -std=c++11 -I$(CAPI_PSL_DIR) -I$(CAPI_PSL_DIR)/pslse/pslse -L$(CAPI_PSL_DIR)/pslse/pslse -I$(CAPI_PSL_DIR) -o $@ $< $(CAPI_PSL_DIR)/pslse/pslse/libcxl.a -lpthread -lcxl
	
remote:
	ssh parallels@10.211.55.6 "make -C /home/jcassidy/src/BlueLink/Examples/Memcopy host_memcopy" 

# make the Verilog target
mkMemcopyTB.v: Test_Memcopy.bsv Memcopy.bsv
	bsc -p $(BLUESPEC_PATH) -u $<
	bsc -p $(BLUESPEC_PATH) -verilog -g mkMemcopyTB $<

clean:
	rm -f *.o *.so schedule.* transcript vsim.wlf wlft* *.cxx mk*.c mk*.h pseries_nvram.* *.ba *.bo mkMemcopyTB.v