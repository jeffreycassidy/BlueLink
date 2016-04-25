IF(CAPI_SIM_FOUND OR CAPI_SYN_FOUND)
    INCLUDE_DIRECTORIES(${CAPI_INCLUDE_DIRS})
    ADD_EXECUTABLE(host_memcopystream host_memcopystream.cpp)
    TARGET_LINK_LIBRARIES(host_memcopystream BlueLinkHost pthread ${CAPI_CXL_LIBRARY})
ENDIF()

IF(USE_BLUESPEC)
    ADD_BSV_PACKAGE(MemcopyStream ResourceManager ReadStream WriteStream CmdArbiter MMIO DedicatedAFU AFUShims)
    ADD_BLUESPEC_VERILOG_OUTPUT(MemcopyStream mkMemcopyStreamAFU)
    ADD_BLUESPEC_VERILOG_OUTPUT(MemcopyStream mkMemcopyNarrowStreamAFU)
ENDIF()

## Run CAPI sim
IF(CAPI_SIM_FOUND)
    VSIM_ADD_LIBRARY(work)
    VSIM_MAP_LIBRARY(bsvlibs ${CMAKE_BINARY_DIR}/bsvlibs)
    VSIM_MAP_LIBRARY(bsvaltera ${CMAKE_BINARY_DIR}/bsvaltera)

    ADD_CAPI_SIM(Stream16k      mkMemcopyStreamAFU          host_memcopystream nullargs.txt)
    ADD_CAPI_SIM(Stream4kNarrow mkMemcopyNarrowStreamAFU    host_memcopystream nullargs.txt)
ENDIF()
