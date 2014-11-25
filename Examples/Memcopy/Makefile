ifndef BLUELOGIC
    BLUELOGIC=../../../BlueLogic
endif

ifndef BLUELINK
	BLUELINK=../..
endif

BLUESPEC_PATH=+:$(BLUELOGIC)/Pipeline:$(BLUELINK)/Core:$(BLUELOGIC)/Convenience

# make the Verilog target
mkMemcopyTB.v: Test_Memcopy.bsv Memcopy.bsv
	bsc -p $(BLUESPEC_PATH) -u $<
	bsc -p $(BLUESPEC_PATH) -verilog -g mkMemcopyTB $<

clean:
	rm -f *.o *.so schedule.* transcript vsim.wlf wlft* *.cxx mk*.c mk*.h pseries_nvram.* *.ba *.bo mkMemcopyTB.v
