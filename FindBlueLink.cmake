SET(BLUELINK_ROOT "" CACHE PATH "")

SET(BLUELINK_INCLUDE_DIR "${BLUELINK_ROOT}/Host" CACHE PATH "")
SET(BLUELINK_LIBRARY_DIR "${BLUELINK_ROOT}/Build/Release/lib" CACHE PATH "")

SET(BLUELINK_HA_ASSIGNMENT_DELAY "#1" CACHE STRING "Host to AFU assignment delay for Verilog simulations")

LIST(APPEND BLUELINK_LIBRARIES BlueLinkHost)

LINK_DIRECTORIES(${BLUELINK_LIBRARY_DIR})

FIND_PACKAGE(CAPI REQUIRED)



## Compilation commands for CAPI simulation testbenches

IF(CAPI_SIM_FOUND)
    FIND_PACKAGE(VSIM REQUIRED)

    FUNCTION(ADD_CAPI_SIM TESTCASENAME MODNAME HOSTPROG HOSTPROGARGFILE)
        ADD_CUSTOM_TARGET(capi_${TESTCASENAME} DEPENDS verilog_${MODNAME} ${HOSTPROG})

        ADD_CUSTOM_COMMAND(TARGET capi_${TESTCASENAME} POST_BUILD
        # copy PSLSE config files
            COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/pslse.parms   ${CMAKE_CURRENT_BINARY_DIR}
            COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/shim_host.dat ${CMAKE_CURRENT_BINARY_DIR}
            COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/pslse_server.dat ${CMAKE_CURRENT_BINARY_DIR}

        # compile wrapper with appropriate DUT module instance
            COMMAND ${VSIM_VLOG_EXECUTABLE} -work work +define+MODULENAME=${MODNAME} +define+HA_ASSIGNMENT_DELAY=${BLUELINK_HA_ASSIGNMENT_DELAY} ${BLUELINK_ROOT}/PSLVerilog/top.v ${BLUELINK_ROOT}/PSLVerilog/revwrap.v

        # compile the AFU
            COMMAND ${VSIM_VLOG_EXECUTABLE} -work work ${MODNAME}.v

        # simulate
            COMMAND ${VSIM_VSIM_EXECUTABLE} -batch -onfinish exit -logfile transcript -t 1ns -L altera_mf_ver -L bsvlibs -L bsvaltera -L work -do "run -all" -pli ${CAPI_SIM_PLI_DRIVER} ${MODNAME}_pslse_top
        )
    ENDFUNCTION()
ENDIF()
