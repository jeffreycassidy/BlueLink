#.rst:
# BluespecConfig
# ------------
#
# Configures the Bluespec compiler and Bluesim simulator

# This will define the following variables:
#
#	Bluespec_FOUND
#	Bluespec_DIR
#
# TODO in future:
#	Bluespec_VERSION
#
# and the following imported targets:
#
#
# and the following functions:
#
#

# ======
# (copyright TBD)
# =======

IF(NOT "$ENV{BLUESPECDIR}" STREQUAL "")
	MESSAGE("BLUESPECDIR is present and set to value $ENV{BLUESPECDIR}")
	SET(Bluespec_DIR $ENV{BLUESPECDIR} CACHE PATH "Path to Bluespec lib dir, as typically set during bsc install")
    SET(BLUESPEC_ROOT $ENV{BLUESPECDIR}/.. CACHE PATH "Bluespec root dir")
    SET(BLUESPEC_VPI32_LIBRARY_DIR $ENV{BLUESPECDIR}/VPI/g++4 CACHE PATH "Path to libbdpi.so for 32 vsim")
    SET(BLUESPEC_VPI64_LIBRARY_DIR $ENV{BLUESPECDIR}/VPI/g++4_64 CACHE PATH "Path to libbdpi.so for 32 vsim")
    SET(BLUESPEC_VPI_INCLUDE_DIR $ENV{BLUESPECDIR}/VPI CACHE PATH "Path to bdpi.h")
    SET(Bluespec_FOUND ON)
ELSE()
	MESSAGE("BLUESPECDIR is not present - faulty install or environment not set up?")
ENDIF()

IF(NOT Bluespec_FOUND)
	RETURN()
ENDIF()


## Bluespec-specific options
SET(BLUESPEC_VERILOG_SIM_ASSIGNMENT_DELAY "#1" CACHE STRING "Assignment delay to set")
SET(BLUESPEC_VERILOG_SIM_TIMESCALE "1ns/1ns" CACHE STRING "-timescale option for simulation")

## Bluespec compiler paths
SET(BLUESPEC_BSC_PATH "+" CACHE PATH "Include path for Bluespec")
SET(BLUESPEC_BSC_BDIR "${CMAKE_BINARY_DIR}/bdir" CACHE PATH "Directory for .ba and .bo objects" )
SET(BLUESPEC_BSC_EXECUTABLE "/usr/local/Bluespec/bin/bsc")
MARK_AS_ADVANCED(BLUESPEC_BSC_BDIR)

## Bluespec compilation options
SET(BLUESPEC_BSC_AGGRESSIVE_CONDITIONS ON CACHE BOOL "-aggressive-conditions switch")
SET(BLUESPEC_BSC_ASSERTIONS ON CACHE BOOL "-check-assert switch")

SET(BLUESPEC_BSC_OPTIONS "" CACHE STRING "Additional compile (sim & verilog) switches not listed above")
SET(BLUESPEC_BSC_SIM_OPTIONS "" CACHE STRING "Additional simulation switches not listed above")
SET(BLUESPEC_BSC_VERILOG_OPTIONS "-opt-undetermined-vals -unspecified-to X" CACHE STRING "Additional Verilog switches not listed above")

SET(BLUESPEC_BLUESIM_LIBRARY_DIRS "" CACHE STRING "Additional -L paths when compiling bsc -sim")


MARK_AS_ADVANCED(
	BLUESPEC_BSC_OPTIONS
	BLUESPEC_BSC_SIM_OPTIONS
	BLUESPEC_VERILOG_OPTIONS
)

IF(BLUESPEC_BSC_AGGRESSIVE_CONDITIONS)
	LIST (APPEND BLUESPEC_BSC_OPTIONS "-aggressive-conditions")
ENDIF()

IF(BLUESPEC_BSC_ASSERTIONS)
	LIST(APPEND BLUESPEC_BSC_OPTIONS "-check-assert")
ENDIF()

SET(BLUESPEC_BSC_SIM_OPTIONS "-sim")

LIST(APPEND BLUESPEC_BSC_VERILOG_OPTIONS "-verilog")
LIST(APPEND BLUESPEC_BSC_VERILOG_OPTIONS ${BLUESPEC_BSC_OPTIONS})
STRING(REPLACE " " ";" BSCV "${BLUESPEC_BSC_VERILOG_OPTIONS}")

#MESSAGE("Pre-expansion: ${BLUESPEC_BSC_VERILOG_OPTIONS}")
#MESSAGE("BSC verilog options: ${BSCV}")

FILE(MAKE_DIRECTORY ${BLUESPEC_BSC_BDIR})

## Adds a compilation target for ${FN}.bsv and a target named ${FN}
FUNCTION(ADD_BSV_PACKAGE PACKAGE)

    SET(ARGNLIST ${ARGN})

    FOREACH(PKGDEP IN LISTS ARGNLIST)
        LIST(APPEND PKGDEPS ${BLUESPEC_BSC_BDIR}/${PKGDEP}.bo)
#        SET(PKGDEPS "${PKGDEPS} ${BLUESPEC_BSC_BDIR}/${PKGDEP}.bo")
    ENDFOREACH()

	ADD_CUSTOM_COMMAND(
		OUTPUT ${BLUESPEC_BSC_BDIR}/${PACKAGE}.bo
		COMMAND ${BLUESPEC_BSC_EXECUTABLE} ${BLUESPEC_BSC_OPTIONS} -p ${BLUESPEC_BSC_PATH} -bdir ${BLUESPEC_BSC_BDIR} ${CMAKE_CURRENT_SOURCE_DIR}/${PACKAGE}.bsv
		DEPENDS ${CMAKE_CURRENT_SOURCE_DIR}/${PACKAGE}.bsv ${PKGDEPS}
		WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
		)

	ADD_CUSTOM_TARGET(${PACKAGE} ALL DEPENDS ${BLUESPEC_BSC_BDIR}/${PACKAGE}.bo)

    IF(ARGNLIST)
#        MESSAGE("Dependencies of ${PACKAGE}: ${ARGNLIST}")
#        MESSAGE("File deps: ${PKGDEPS}")
        ADD_DEPENDENCIES(${PACKAGE} ${ARGNLIST})
    ENDIF()
ENDFUNCTION()

## Adds a compilation target for ${FN}.bsv and a target named ${FN}
##      Difference is that it takes the .bsv from the current _binary_ dir instead of source dir
FUNCTION(ADD_GENERATED_BSV_PACKAGE PACKAGE)

	ADD_CUSTOM_COMMAND(
		OUTPUT ${BLUESPEC_BSC_BDIR}/${PACKAGE}.bo
		COMMAND ${BLUESPEC_BSC_EXECUTABLE} ${BLUESPEC_BSC_OPTIONS} -p ${BLUESPEC_BSC_PATH} -bdir ${BLUESPEC_BSC_BDIR} ${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE}.bsv
		DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${PACKAGE}.bsv
		WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
		)

	ADD_CUSTOM_TARGET(${PACKAGE} DEPENDS ${BLUESPEC_BSC_BDIR}/${PACKAGE}.bo)
ENDFUNCTION()

## Adds a testbench file from the named package
FUNCTION(ADD_BSV_TESTBENCH PACKAGE)
	ADD_BSV_PACKAGE(${PACKAGE} ${ARGN})
ENDFUNCTION()

## Adds a testcase from a previously-added testbench package
## 		Compiles mkTB_${TESTCASE} from package ${PACKAGE}, producing output file test_${TESTCASE}
## Any additional args are interpreted as -l <lib>
FUNCTION(ADD_BLUESIM_TESTCASE PACKAGE TESTCASE)

    # Create the target
	ADD_CUSTOM_TARGET(${TESTCASE} DEPENDS ${PACKAGE} ${CMAKE_CURRENT_BINARY_DIR}/test_${TESTCASE})




    ## Convert list of additional BDPI libs to string
    SET(ARGNLIST ${ARGN})

    FOREACH(BDPI_LIB IN LISTS ARGNLIST)
        LIST(APPEND BDPI_LIB_ARGS "-l;${BDPI_LIB}")
        ADD_DEPENDENCIES(${TESTCASE} ${BDPI_LIB})
    ENDFOREACH()

#    MESSAGE("BDPI -l args for ${TESTCASE}: ${BDPI_LIB_ARGS}")



    ## Add BDPI link library dirs
    LIST(APPEND BLUESPEC_BLUESIM_LIBRARY_DIRS ${CMAKE_BINARY_DIR}/lib)
    LIST(APPEND BLUESPEC_BLUESIM_LIBRARY_DIRS ${CMAKE_CURRENT_BINARY_DIR})

    # Make LD_LIBRARY_PATH
    STRING(REPLACE ";" ":" LDLIB "${BLUESPEC_BLUESIM_LIBRARY_DIRS}")

    # BDPI library arguments
    FOREACH(BDPI_LIB_DIR IN LISTS BLUESPEC_BLUESIM_LIBRARY_DIRS)
        LIST(APPEND BDPI_LIB_DIR_ARGS "-L;${BDPI_LIB_DIR}")
    ENDFOREACH()

#    MESSAGE("BDPI_LIB_DIR_ARGS=${BDPI_LIB_DIR_ARGS}")
    MESSAGE("LD_LIBRARY_PATH=${LDLIB}")


#    MESSAGE("BDPI -L args for ${TESTCASE}: ${BDPI_LIB_DIR_ARGS}")

	ADD_CUSTOM_COMMAND(
		OUTPUT test_${TESTCASE}
		COMMAND ${BLUESPEC_BSC_EXECUTABLE} ${BLUESPEC_BSC_SIM_OPTIONS} -g mkTB_${TESTCASE} -bdir ${BLUESPEC_BSC_BDIR} -p ${BLUESPEC_BSC_PATH} ${CMAKE_CURRENT_SOURCE_DIR}/${PACKAGE}.bsv 
		COMMAND ${BLUESPEC_BSC_EXECUTABLE} ${BLUESPEC_BSC_SIM_OPTIONS} -e mkTB_${TESTCASE} -bdir ${BLUESPEC_BSC_BDIR} -p ${BLUESPEC_BSC_PATH} ${BDPI_LIB_DIR_ARGS} ${BDPI_LIB_ARGS} -o ${CMAKE_CURRENT_BINARY_DIR}/test_${TESTCASE}
		DEPENDS ${BLUESPEC_BSC_BDIR}/${PACKAGE}.bo
		WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
	)


    ADD_CUSTOM_TARGET(check_${TESTCASE} DEPENDS ${TESTCASE})
    ADD_CUSTOM_COMMAND(TARGET check_${TESTCASE} POST_BUILD
        COMMAND env LD_LIBRARY_PATH=${LDLIB} ./test_${TESTCASE}
        WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})

ENDFUNCTION()



FUNCTION(ADD_BLUESPEC_VERILOG_OUTPUT PACKAGE MODULE)

## NOTE: BSC -verilog outputs its files to the same folder as the source file, NOT its working directory

	ADD_CUSTOM_COMMAND(
		OUTPUT ${MODULE}.v
        COMMAND ${CMAKE_COMMAND} -E copy ${CMAKE_CURRENT_SOURCE_DIR}/${PACKAGE}.bsv ${CMAKE_CURRENT_BINARY_DIR}
		COMMAND ${BLUESPEC_BSC_EXECUTABLE} ${BSCV} -g ${MODULE} -p ${BLUESPEC_BSC_PATH} -bdir ${BLUESPEC_BSC_BDIR} ${PACKAGE}.bsv 
		DEPENDS ${BLUESPEC_BSC_BDIR}/${PACKAGE}.bo ${CMAKE_CURRENT_SOURCE_DIR}/${PACKAGE}.bsv
		WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
	)

    ADD_CUSTOM_TARGET(verilog_${MODULE} DEPENDS ${PACKAGE} ${CMAKE_CURRENT_BINARY_DIR}/${MODULE}.v)

ENDFUNCTION()



#### Compilation of Bluespec libraries


IF (BLUESPEC_VERILOG_SIM_ASSIGNMENT_DELAY)
    LIST(APPEND BLUESPEC_VERILOG_LIB_OPTS +define+BSV_ASSIGNMENT_DELAY=${BLUESPEC_VERILOG_SIM_ASSIGNMENT_DELAY})
ENDIF()

IF(BLUESPEC_VERILOG_SIM_TIMESCALE)
    LIST(APPEND BLUESPEC_VERILOG_LIB_OPTS -timescale ${BLUESPEC_VERILOG_SIM_TIMESCALE})
ENDIF()


## Compile the Bluespec Verilog IP

OPTION(USE_VSIM OFF)

IF(USE_VSIM)
    FIND_PACKAGE(VSIM REQUIRED)
ENDIF()

IF(VSIM_FOUND)
    FILE(GLOB BLUESPEC_LIB_VERILOG_SOURCES ${BLUESPEC_ROOT}/lib/Verilog/*.v)
    MESSAGE("Bluespec IP folder: ${BLUESPEC_ROOT}/lib/Verilog")
    LIST(APPEND BLUESPEC_VERILOG_LIB_OPTS "+define+TOP=foo")

    VSIM_ADD_LIBRARY(bsvlibs)

    EXECUTE_PROCESS(
        COMMAND ${VSIM_VLOG_EXECUTABLE} -work bsvlibs ${BLUESPEC_VERILOG_LIB_OPTS} ${BLUESPEC_LIB_VERILOG_SOURCES}
        WORKING_DIRECTORY ${CMAKE_BINARY_DIR})


    FUNCTION(ADD_BLUESPEC_VERILOG_TESTBENCH PACKAGE)
        ADD_BSV_PACKAGE(${PACKAGE} ${ARGN})
    ENDFUNCTION()

    FUNCTION(ADD_BLUESPEC_VERILOG_TESTCASE PACKAGE MODULE)
        ADD_BLUESPEC_VERILOG_OUTPUT(${PACKAGE} ${MODULE})

        # Additional args are VPI libs

        FOREACH(VPILIB ${ARGN})
            LIST(APPEND VPIARG -pli ${VPILIB})
        ENDFOREACH()

        STRING(REPLACE ";" " " VPIARGSTR "${VPIARG}")

        MESSAGE("Args: ${VPIARG}")

        SET(VSIM_ARGS "vsim -t 1ns -L altera_mf_ver -L bsvlibs -L work -L bsvaltera ${VPIARGSTR} ${MODULE}; onfinish exit; force -drive CLK 1'b0, 1'b1 @ 5 -repeat 10; force -drive RST_N 1'b0, 1'b1 @ 10; run -all;")

        ADD_CUSTOM_TARGET(vsimrun_${MODULE}
            COMMAND ${VSIM_VLOG_EXECUTABLE} -timescale 1ns/1ns ${MODULE}.v
            COMMAND ${VSIM_VSIM_EXECUTABLE} -c -do "${VSIM_ARGS}"
            DEPENDS ${MODULE}.v
            WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
            VERBATIM)

    ENDFUNCTION()
        

    ## Creates a 32bit VPI library named lib, after building BSV module verilog_MODULE from package PACKAGE
    ## It generates the necessary init files and links them in
    # ADD_VPI_LIBRARY(PACKAGE MODNAME LIB SOURCES...)
    
    FUNCTION(ADD_VPI_LIBRARY PACKAGE MODNAME LIBNAME)
        LINK_DIRECTORIES(${BLUESPEC_VPI32_LIBRARY_DIR})
    
        SET(SOURCES ${ARGN})
        LIST(APPEND SOURCES vpi_init_funcs.c)
    
        ADD_LIBRARY(${LIBNAME} SHARED ${SOURCES})
    
    ## create vpi_init_funcs.c

        ADD_DEPENDENCIES(${LIBNAME} verilog_${MODNAME})
    
        ADD_CUSTOM_COMMAND(
            OUTPUT vpi_init_funcs.c
            DEPENDS ${CMAKE_BINARY_DIR}/bdir/${PACKAGE}.bo ${CMAKE_CURRENT_BINARY_DIR}/${MODNAME}.v
            COMMAND ${PERL_EXECUTABLE} ${Bluespec_DIR}/makePLIRegistration.pl vpi_init_funcs.c
            WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR})

        SET_TARGET_PROPERTIES(${LIBNAME} PROPERTIES
            LINK_FLAGS -m32
            INCLUDE_DIRECTORIES "${VSIM_VPI_INCLUDE_DIR};${BDPIDEVICE_INCLUDE_DIR};${BLUESPEC_VPI_INCLUDE_DIR}")
        TARGET_COMPILE_OPTIONS(${LIBNAME} PUBLIC -m32)
    
        ## VERY IMPORTANT: specific libstdc++.so.6 line below prevents problems where a Modelsim version without GLIBCXX.3.4.20 gets
        ## called up and causes a link failure
    
        TARGET_LINK_LIBRARIES(${LIBNAME} bdpi /usr/lib/i386-linux-gnu/libstdc++.so.6 gmp)
    
    ENDFUNCTION()
ENDIF()
