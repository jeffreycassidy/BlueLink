LINK_DIRECTORIES(/home/parallels/remote-build/BDPIDevice/Build/Release/lib)

ADD_LIBRARY(MemScanChainTest SHARED MemScanChainTest.cpp)
TARGET_LINK_LIBRARIES(MemScanChainTest BDPIDeviceBase)

ADD_BSV_PACKAGE(MemScanChain AlteraM20k BRAMStall)
ADD_BSV_TESTBENCH(Test_MemScanChain MemScanChain)

ADD_BLUESIM_TESTCASE(Test_MemScanChain MSC_SW BDPIDeviceBase MemScanChainTest)
