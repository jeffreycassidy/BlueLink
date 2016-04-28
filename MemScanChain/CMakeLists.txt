FIND_PACKAGE(BDPIDevice REQUIRED)

LINK_DIRECTORIES(/home/parallels/remote-build/BDPIDevice/Build/Release/lib)

ADD_LIBRARY(MemScanChainTest SHARED MemScanChainTest.cpp)
TARGET_LINK_LIBRARIES(MemScanChainTest BDPIDeviceBase)

LINK_DIRECTORIES(${BLUESPEC_VPI32_LIBRARY_DIR})
ADD_LIBRARY(MemScanChainTestVPI SHARED MemScanChainTest.cpp vpi_init_funcs.c)
SET_TARGET_PROPERTIES(MemScanChainTestVPI PROPERTIES
    LINK_FLAGS -m32
    INCLUDE_DIRECTORIES "${VSIM_VPI_INCLUDE_DIR};${BDPIDEVICE_INCLUDE_DIR};${BLUESPEC_VPI_INCLUDE_DIR}")
TARGET_COMPILE_OPTIONS(MemScanChainTestVPI PUBLIC -m32)
# Use g++4_64 for 64b Modelsim


## VERY IMPORTANT: specific libstdc++.so.6 line below prevents problems where a Modelsim version without GLIBCXX.3.4.20 gets
## called up
 
TARGET_LINK_LIBRARIES(MemScanChainTestVPI BDPIDeviceBase_32 bdpi /usr/lib/i386-linux-gnu/libstdc++.so.6 gmp)

ADD_BSV_PACKAGE(MemScanChain AlteraM20k BRAMStall)
ADD_BSV_TESTBENCH(Test_MemScanChain MemScanChain)


#### Modelsim testbench setup

VSIM_MAP_LIBRARY(bsvlibs ../bsvlibs)
VSIM_MAP_LIBRARY(bsvaltera ../bsvaltera)

ADD_BLUESPEC_VERILOG_TESTCASE(Test_MemScanChain mkTB_MSC_SW ../lib/libMemScanChainTestVPI.so)

ADD_CUSTOM_COMMAND(
    OUTPUT vpi_init_funcs.c
    COMMAND ${PERL_EXECUTABLE} ${CMAKE_SOURCE_DIR}/makePLIRegistration.pl vpi_init_funcs.c
    DEPENDS Test_MemScanChain
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})

## VPI registration functions
