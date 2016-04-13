## TODO: Components for sim vs syn

SET(CAPI_ROOT               "" CACHE PATH "")

OPTION(CAPI_SIM OFF)
OPTION(CAPI_SYN OFF)

SET(CAPI_BUILD_TYPE SIM CACHE STRING "SIM or SYN version of libcxl")


IF(CAPI_SIM)

    SET(CAPI_PSLSE_ROOT 		    "${CAPI_ROOT}/pslse"                            CACHE PATH "")
    
    SET(CAPI_SIM_INCLUDE_DIR 	    "${CAPI_PSLSE_ROOT}/libcxl"                     CACHE PATH "")
    SET(CAPI_SIM_LIB_DIR            "${CAPI_PSLSE_ROOT}/libcxl"                     CACHE PATH "Path containing libcxl.so")
    SET(CAPI_SIM_PSLSE_EXECUTABLE	"${CAPI_PSLSE_ROOT}/pslse/pslse"		        CACHE FILE "")
    SET(CAPI_SIM_HOST 				"localhost" 	                                CACHE STRING "")
    SET(CAPI_SIM_PORT 				"16384" 	                                    CACHE STRING "")
    SET(CAPI_SIM_SHIM_PORT          "32768"                                         CACHE STRING "")
    SET(CAPI_SIM_PLI_DRIVER			"${CAPI_PSLSE_ROOT}/afu_driver/src/libvpi.so"	CACHE PATH "")
    
    MARK_AS_ADVANCED(
    	CAPI_SIM_LIBRARY
    	CAPI_SIM_AFUDRIVER
    	CAPI_SIM_PSLSE_EXECUTABLE
    	CAPI_SYN_LIBRARY)

ENDIF()


IF(CAPI_SYN)

    SET(CAPI_SYN_INCLUDE_DIR 	    "${CAPI_ROOT}/libcxl" CACHE PATH "")
    SET(CAPI_SYN_LIB_DIR            "${CAPI_ROOT}/libcxl" CACHE PATH "")

ENDIF()

IF(${CAPI_BUILD_TYPE} STREQUAL SIM)
    SET(CAPI_INCLUDE_DIRS ${CAPI_SIM_INCLUDE_DIR})
    SET(CAPI_LIB_DIRS ${CAPI_SIM_LIB_DIR})
    SET(CAPI_CXL_LIBRARY ${CAPI_SIM_LIB_DIR}/libcxl.so)
ELSE()
    SET(CAPI_INCLUDE_DIRS ${CAPI_SYN_INCLUDE_DIR})
    SET(CAPI_LIB_DIRS ${CAPI_SYN_LIB_DIR})
    SET(CAPI_CXL_LIBRARY ${CAPI_SYN_LIB_DIR}/libcxl.so)
ENDIF()

SET(CAPI_FOUND ON)

FUNCTION(ADD_CAPI_SIM TESTCASENAME MODNAME HOSTPROG HOSTPROGARGFILE)
    ADD_CUSTOM_TARGET(capi_${TESTCASENAME} DEPENDS verilog_${MODNAME} ${HOSTPROG})

    ADD_CUSTOM_COMMAND(TARGET capi_${TESTCASENAME} POST_BUILD
        COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/pslse.parms   ${CMAKE_CURRENT_BINARY_DIR}
        COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/shim_host.dat ${CMAKE_CURRENT_BINARY_DIR}
        COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/pslse_server.dat ${CMAKE_CURRENT_BINARY_DIR}
        COMMAND ${VSIM_VSIM_EXECUTABLE} -batch -onfinish exit -logfile transcript -t 1ns -L altera_mf_ver -L bsvlibs -L bsvaltera -L work -do "run -all" -pli ${CAPI_SIM_PLI_DRIVER} ${MODNAME}_pslse_top
    )
ENDFUNCTION()
