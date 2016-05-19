IF(Bluespec_FOUND)
	ADD_BSV_PACKAGE(CreditIfc)
	ADD_BSV_TESTBENCH(Test_CreditIfc CreditIfc)

	ADD_BLUESIM_TESTCASE(Test_CreditIfc mkTB_Simple)

    ADD_BSV_PACKAGE(MulticycleWire)
    ADD_BSV_TESTBENCH(Test_MMIO MulticycleWire)

    ADD_BLUESIM_TESTCASE(Test_MMIO mkTB_MMIO)

    ADD_BLUESPEC_VERILOG_OUTPUT(Test_MMIO mkSyn_ReadSnapshot)
ENDIF()
