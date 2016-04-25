SET(CAPI_ROOT               "" CACHE PATH "")

OPTION(CAPI_SIM OFF)
OPTION(CAPI_SYN OFF)

## Set up simulation version of CAPI

IF(CAPI_SIM)
    IF (CAPI_SIM_ROOT)
	    SET(CAPI_SIM_FOUND ON)
        SET(CAPI_SIM_INCLUDE_DIR 	    "${CAPI_SIM_ROOT}/libcxl"                       CACHE PATH "")
        SET(CAPI_SIM_LIBRARY_DIR        "${CAPI_SIM_ROOT}/libcxl"                       CACHE PATH "Path containing libcxl.so")

        SET(CAPI_SIM_PSLSE_EXECUTABLE	"${CAPI_SIM_ROOT}/pslse/pslse"	                CACHE FILE "")
        SET(CAPI_SIM_HOST 				"localhost" 	                                CACHE STRING "")
        SET(CAPI_SIM_PORT 				"16384" 	                                    CACHE STRING "")
        SET(CAPI_SIM_SHIM_PORT          "32768"                                         CACHE STRING "")
        SET(CAPI_SIM_PLI_DRIVER			"${CAPI_SIM_ROOT}/afu_driver/src/libvpi.so"	    CACHE PATH "")
    
        MARK_AS_ADVANCED(
    	    CAPI_SIM_LIBRARY
    	    CAPI_SIM_AFUDRIVER
    	    CAPI_SIM_PSLSE_EXECUTABLE
    	    CAPI_SYN_LIBRARY)
    ELSE()
        SET(CAPI_SIM_ROOT "${CAPI_ROOT}/pslse" CACHE PATH "Location of PSLSE version of libcxl")        
    ENDIF()
ENDIF()

IF(CAPI_SIM AND CAPI_SYN)
	SET(CAPI_BUILD_TYPE SIM CACHE STRING "SIM or SYN version of libcxl")
ENDIF()


## Set up synthesis version of CAPI lib

IF(CAPI_SYN)
    IF (CAPI_SYN_ROOT)
    	SET(CAPI_SYN_FOUND ON)
        SET(CAPI_SYN_INCLUDE_DIR 	    "${CAPI_SYN_ROOT}/libcxl" CACHE PATH "")
        SET(CAPI_SYN_LIBRARY_DIR        "${CAPI_SYN_ROOT}/libcxl" CACHE PATH "")
    ELSE()
        SET(CAPI_SYN_ROOT "${CAPI_ROOT}/libcxl" CACHE PATH "")
    ENDIF()
ENDIF()




## Switch between synthesis and simulation options based on CAPI_BUILD_TYPE

IF("${CAPI_BUILD_TYPE}" STREQUAL "SIM")
    SET(CAPI_INCLUDE_DIR ${CAPI_SIM_INCLUDE_DIR})
    SET(CAPI_LIBRARY_DIR ${CAPI_SIM_LIBRARY_DIR})
    SET(CAPI_CXL_LIBRARY ${CAPI_SIM_LIBRARY_DIR}/libcxl.so)
    SET(CAPI_LIBRARIES ${CAPI_CXL_LIBRARY})
ELSE()
    SET(CAPI_INCLUDE_DIR ${CAPI_SYN_INCLUDE_DIR})
    SET(CAPI_LIBRARY_DIR ${CAPI_SYN_LIBRARY_DIR})
    SET(CAPI_CXL_LIBRARY ${CAPI_SYN_LIBRARY_DIR}/libcxl.so)
ENDIF()

LIST(APPEND CAPI_LIBRARIES ${CAPI_CXL_LIBRARY})
