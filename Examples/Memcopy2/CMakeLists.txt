## Setup Modelsim

EXECUTE_PROCESS(
    COMMAND ${VSIM_VLIB_EXECUTABLE} work
    COMMAND ${VSIM_VMAP_EXECUTABLE} bsvlibs ${CMAKE_BINARY_DIR}/bsvlibs
    )

INCLUDE_DIRECTORIES(${CAPI_INCLUDE_DIRS})
ADD_EXECUTABLE(host_memcopy2 host_memcopy2.cpp)
TARGET_LINK_LIBRARIES(host_memcopy2 BlueLinkHost pthread ${CAPI_CXL_LIBRARY})

ADD_BSV_PACKAGE(Memcopy2)
ADD_DEPENDENCIES(Memcopy2 Core AFUShims DedicatedAFU ResourceManager)

ADD_BLUESPEC_VERILOG_OUTPUT(Memcopy2 mkMemcopy2AFU)



## Post-build commands for CAPI simulation

ADD_CUSTOM_COMMAND(TARGET verilog_mkMemcopy2AFU POST_BUILD
    COMMAND ${VSIM_VLOG_EXECUTABLE} -work work mkMemcopy2AFU.v
    COMMAND ${VSIM_VLOG_EXECUTABLE} -work work +define+MODULENAME=mkMemcopy2AFU +define+HA_ASSIGNMENT_DELAY=${BLUELINK_HA_ASSIGNMENT_DELAY} ${CMAKE_SOURCE_DIR}/PSLVerilog/top.v ${CMAKE_SOURCE_DIR}/PSLVerilog/revwrap.v 
    )


## Run CAPI sim

ADD_CUSTOM_TARGET(sim_Memcopy2 DEPENDS verilog_mkMemcopy2AFU host_memcopy2)

ADD_CUSTOM_COMMAND(TARGET sim_Memcopy2 POST_BUILD
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/pslse.parms   ${CMAKE_CURRENT_BINARY_DIR}
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/shim_host.dat ${CMAKE_CURRENT_BINARY_DIR}
    COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/pslse_server.dat ${CMAKE_CURRENT_BINARY_DIR}
    COMMAND ${VSIM_VSIM_EXECUTABLE} -batch -onfinish exit -logfile transcript -t 1ns -L altera_mf_ver -L bsvlibs -L bsvaltera -L work -do "run -all" -pli ${CAPI_SIM_PLI_DRIVER} mkMemcopy2AFU_pslse_top
    )
