PROJECT(BlueLink)

CMAKE_MINIMUM_REQUIRED(VERSION 3.0)

## C++ options
IF(${CMAKE_VERSION} VERSION_LESS "3.1")
    ADD_DEFINITIONS(-std=c++11)
ELSE()
    SET(CMAKE_CXX_STANDARD 11)
ENDIF()


## Create the CMake package config file
#INCLUDE(FindBlueLink.cmake)
CONFIGURE_FILE(BlueLinkConfig.cmake.in BlueLinkConfig.cmake)

SET(CMAKE_LIBRARY_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/lib)

## Include the parent of the source dir to get BlueLink/... includes
INCLUDE_DIRECTORIES(${CMAKE_SOURCE_DIR}/..)

## Optional components
OPTION(USE_BLUESPEC ON)


## Unit tests
SET(TESTING ON CACHE BOOL "Build unit tests")





IF(TESTING)
	ENABLE_TESTING()
ENDIF()

IF(USE_BLUESPEC)
    FIND_PACKAGE(Bluespec)
ENDIF()

FIND_PACKAGE(CAPI REQUIRED)
FIND_PACKAGE(BlueLink REQUIRED)

FIND_PACKAGE(Boost REQUIRED)
INCLUDE_DIRECTORIES(${Boost_INCLUDE_DIRS})

CONFIGURE_FILE(pslse_server.dat.in pslse_server.dat)
CONFIGURE_FILE(shim_host.dat.in shim_host.dat)
CONFIGURE_FILE(pslse.parms.in pslse.parms)

IF(USE_BLUESPEC)
    ADD_BSV_PACKAGE(CAPIOptions)
    ADD_BSV_PACKAGE(SynthesisOptions)
    ADD_BSV_PACKAGE(ShiftReg)
ENDIF()

ADD_SUBDIRECTORY(Core)
ADD_SUBDIRECTORY(MMIO)
ADD_SUBDIRECTORY(DedicatedAFU)
ADD_SUBDIRECTORY(Altera)
ADD_SUBDIRECTORY(CommandInterface)
ADD_SUBDIRECTORY(MemScanChain)
ADD_SUBDIRECTORY(Stream)
ADD_SUBDIRECTORY(Host)
ADD_SUBDIRECTORY(Examples)
