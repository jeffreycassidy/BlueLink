FIND_PACKAGE(BDPIDevice REQUIRED)

LINK_DIRECTORIES(${BDPIDEVICE_LIBRARY_DIR})

ADD_LIBRARY(MemScanChainTest SHARED MemScanChainTest.cpp)
TARGET_LINK_LIBRARIES(MemScanChainTest BDPIDeviceBase)

ADD_EXECUTABLE(BlockRAMGroupTest BlockRAMGroupTest.cpp)
TARGET_LINK_LIBRARIES(BlockRAMGroupTest ${CAPI_LIBRARIES} ${BLUELINK_LIBRARIES})

IF(USE_BLUESPEC)
	ADD_BSV_PACKAGE(BRAMBank)
	ADD_BSV_PACKAGE(MemScanChain AlteraM20k BRAMStall)

	ADD_BSV_TESTBENCH(Test_MemScanChain MemScanChain)

	ADD_BSV_TESTBENCH(Test_BRAMGroup MemScanChain BRAMBank)
	ADD_BSV_TESTBENCH(Test_BRAMGroup_CAPI MemScanChain)
ENDIF()


#### Modelsim environment setup

IF(VSIM_FOUND)
	VSIM_MAP_LIBRARY(bsvlibs ../bsvlibs)
	VSIM_MAP_LIBRARY(bsvaltera ../bsvaltera)
ENDIF()


#### Simple BSV-only testbench
IF(VSIM_FOUND AND USE_BLUESPEC)
	ADD_BLUESPEC_VERILOG_TESTCASE(Test_BRAMGroup mkTB_BRAMGroup)
ENDIF()


#### CAPI testbench (not for synthesis: has internal checking FSM that is way too slow for synthesis)
IF(VSIM_FOUND AND USE_BLUESPEC)
	ADD_BLUESPEC_VERILOG_OUTPUT(Test_BRAMGroup_CAPI mkBRAMGroupCAPI)
	ADD_CAPI_SIM(brg mkBRAMGroupCAPI BlockRAMGroupTest argfile)

ENDIF()


#### C++-based testbenches
IF(VSIM_FOUND AND USE_BLUESPEC)
	ADD_VPI_LIBRARY(Test_MemScanChain mkTB_MSC_SW MemScanChainTestVPI MemScanChainTest.cpp)
	TARGET_LINK_LIBRARIES(MemScanChainTestVPI BDPIDeviceBaseVPI)

	ADD_BLUESPEC_VERILOG_TESTCASE(Test_MemScanChain mkTB_MSC_SW /home/parallels/remote-build/BDPIDevice/Build/Release/lib/libBDPIDeviceBaseVPI.so ../lib/libMemScanChainTestVPI.so)

	ADD_BLUESPEC_VERILOG_TESTCASE(Test_MemScanChain mkTB_MemScanChain4x64 /home/parallels/remote-build/BDPIDevice/Build/Release/lib/libBDPIDeviceBaseVPI.so ../lib/libMemScanChainTestVPI.so)
ENDIF()




#### Synthesis targets

IF(USE_BLUESPEC)
	ADD_BLUESPEC_VERILOG_OUTPUT(Test_BRAMGroup_CAPI mkBRAMGroupCAPI_hw)

	#### Synthesis tests (for timing in isolation)

	# 16 2k x 512b banks = 32k x 512 (16Mb) -> > 300 MHz using 7% ALM and 32% BRAM
	ADD_BLUESPEC_VERILOG_OUTPUT(Test_MemScanChain mkSyn_MemScanChain_2k_16_512)

	# 16 4k x 512b banks = 64k x 512 (32Mb) @ 300 MHz using 7% ALM and 64% BRAM
	ADD_BLUESPEC_VERILOG_OUTPUT(Test_MemScanChain mkSyn_MemScanChain_4k_16_512)

	# 8 8k x 512b banks = 64k x 512 (32Mb) @ 280 MHz using 4% ALM and 64% BRAM
	ADD_BLUESPEC_VERILOG_OUTPUT(Test_MemScanChain mkSyn_MemScanChain_8k_8_512)
ENDIF()