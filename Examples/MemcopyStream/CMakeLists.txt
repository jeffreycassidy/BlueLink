## Setup Modelsim

EXECUTE_PROCESS(
    COMMAND echo "Creating work, bsvlibs, and bsvaltera"
    COMMAND ${VSIM_VLIB_EXECUTABLE} work
    COMMAND ${VSIM_VMAP_EXECUTABLE} bsvlibs ${CMAKE_BINARY_DIR}/bsvlibs
    COMMAND ${VSIM_VMAP_EXECUTABLE} bsvaltera ${CMAKE_BINARY_DIR}/bsvaltera
    WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
    )

INCLUDE_DIRECTORIES(${CAPI_INCLUDE_DIRS})
ADD_EXECUTABLE(host_memcopystream host_memcopystream.cpp)
TARGET_LINK_LIBRARIES(host_memcopystream BlueLinkHost pthread ${CAPI_CXL_LIBRARY})

ADD_BSV_PACKAGE(MemcopyStream ResourceManager ReadStream WriteStream CmdArbiter MMIO DedicatedAFU AFUShims)

ADD_BLUESPEC_VERILOG_OUTPUT(MemcopyStream mkMemcopyStreamAFU)

## Run CAPI sim
ADD_CAPI_SIM(Stream16k mkMemcopyStreamAFU host_memcopystream nullargs.txt)
