IF(Bluespec_FOUND)
    ADD_BSV_PACKAGE(BRAMStall)

    ADD_BSV_PACKAGE(BDPIDevice)
    ADD_BSV_PACKAGE(BDPIPort)
    ADD_BSV_PACKAGE(Ticker)

    ADD_BSV_TESTBENCH(BDPIDeviceTest)
    ADD_DEPENDENCIES(BDPIDeviceTest Ticker BDPIDevice BDPIPort)
    
    ADD_BLUESIM_TESTCASE(BDPIDeviceTest Ticker10 BDPIDeviceBase BDPITicker)
ENDIF()


## BDPIDevice/BDPIPort C++ libraries
ADD_LIBRARY(BDPIDeviceBase SHARED BDPIDevice.cpp BDPIPort.cpp BDPIDeviceFactory.cpp BDPIDeviceFactoryRegistry.cpp)

ADD_LIBRARY(BDPITicker SHARED Ticker.cpp)
TARGET_LINK_LIBRARIES(BDPITicker BDPIDeviceBase)
