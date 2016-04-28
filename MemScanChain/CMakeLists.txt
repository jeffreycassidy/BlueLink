FIND_PACKAGE(BDPIDevice REQUIRED)

LINK_DIRECTORIES(/home/parallels/remote-build/BDPIDevice/Build/Release/lib)

ADD_LIBRARY(MemScanChainTest SHARED MemScanChainTest.cpp)
TARGET_LINK_LIBRARIES(MemScanChainTest BDPIDeviceBase)




ADD_BSV_PACKAGE(MemScanChain AlteraM20k BRAMStall)

ADD_BSV_TESTBENCH(Test_MemScanChain MemScanChain)

ADD_BSV_TESTBENCH(Test_BRAMGroup MemScanChain)


#### Modelsim environment setup

VSIM_MAP_LIBRARY(bsvlibs ../bsvlibs)
VSIM_MAP_LIBRARY(bsvaltera ../bsvaltera)


#### Simple BSV-only testbench

ADD_BLUESPEC_VERILOG_TESTCASE(Test_BRAMGroup mkTB_BRAMGroup)


#### CAPI testbench

ADD_BSV_TESTBENCH(Test_BRAMGroup_CAPI MemScanChain)
ADD_BLUESPEC_VERILOG_OUTPUT(Test_BRAMGroup_CAPI mkBRAMGroupCAPI)
ADD_CAPI_SIM(brg mkBRAMGroupCAPI BlockRAMGroupTest argfile)

ADD_EXECUTABLE(BlockRAMGroupTest BlockRAMGroupTest.cpp)
TARGET_LINK_LIBRARIES(BlockRAMGroupTest ${CAPI_LIBRARIES} ${BLUELINK_LIBRARIES})


#### C++-based testbenches

ADD_VPI_LIBRARY(Test_MemScanChain mkTB_MSC_SW MemScanChainTestVPI MemScanChainTest.cpp)
TARGET_LINK_LIBRARIES(MemScanChainTestVPI BDPIDeviceBaseVPI)

ADD_BLUESPEC_VERILOG_TESTCASE(Test_MemScanChain mkTB_MSC_SW /home/parallels/remote-build/BDPIDevice/Build/Release/lib/libBDPIDeviceBaseVPI.so ../lib/libMemScanChainTestVPI.so)

ADD_BLUESPEC_VERILOG_TESTCASE(Test_MemScanChain mkTB_MemScanChain4x64 /home/parallels/remote-build/BDPIDevice/Build/Release/lib/libBDPIDeviceBaseVPI.so ../lib/libMemScanChainTestVPI.so)




#### Synthesis tests (for timing)

# 16 2k x 512b banks = 32k x 512 (16Mb) -> > 300 MHz using 7% ALM and 32% BRAM
ADD_BLUESPEC_VERILOG_OUTPUT(Test_MemScanChain mkSyn_MemScanChain_2k_16_512)

# 16 4k x 512b banks = 64k x 512 (32Mb) @ 300 MHz using 7% ALM and 64% BRAM
ADD_BLUESPEC_VERILOG_OUTPUT(Test_MemScanChain mkSyn_MemScanChain_4k_16_512)

# 8 8k x 512b banks = 64k x 512 (32Mb) @ 280 MHz using 4% ALM and 64% BRAM
ADD_BLUESPEC_VERILOG_OUTPUT(Test_MemScanChain mkSyn_MemScanChain_8k_8_512)
