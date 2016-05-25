IF(Bluespec_FOUND)
	ADD_BSV_PACKAGE(CreditIfc)
	ADD_BSV_TESTBENCH(Test_CreditIfc CreditIfc)

	ADD_BLUESIM_TESTCASE(Test_CreditIfc mkTB_Simple)
ENDIF()
