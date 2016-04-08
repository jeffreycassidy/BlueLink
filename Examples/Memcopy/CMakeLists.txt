INCLUDE_DIRECTORIES(${CAPI_INCLUDE_DIRS})
ADD_EXECUTABLE(host_memcopy host_memcopy.cpp)
TARGET_LINK_LIBRARIES(host_memcopy BlueLinkHost pthread ${CAPI_CXL_LIBRARY})

ADD_BSV_PACKAGE(Memcopy)
ADD_DEPENDENCIES(Memcopy Core AFUShims)

ADD_BLUESPEC_VERILOG_OUTPUT(Memcopy mkMemcopyAFU)



## Post-build commands for CAPI simulation

ADD_CUSTOM_COMMAND(TARGET verilog_mkMemcopyAFU POST_BUILD
    COMMAND ${VSIM_VLOG_EXECUTABLE} -work work mkMemcopyAFU.v
    COMMAND ${VSIM_VLOG_EXECUTABLE} -work work +define+MODULENAME=mkMemcopyAFU +define+HA_ASSIGNMENT_DELAY=${BLUELINK_HA_ASSIGNMENT_DELAY} ${CMAKE_SOURCE_DIR}/PSLVerilog/top.v ${CMAKE_SOURCE_DIR}/PSLVerilog/revwrap.v 
    )


## Run CAPI sim

ADD_CUSTOM_TARGET(sim DEPENDS verilog_mkMemcopyAFU host_memcopy)

ADD_CUSTOM_COMMAND(TARGET sim POST_BUILD
    COMMAND ${VSIM_VSIM_EXECUTABLE} -batch -onfinish exit -L altera_mf_ver -L bsvlibs -L work -do "run -all" -pli ${CAPI_SIM_PLI_DRIVER} mkMemcopyAFU_pslse_top
    )
