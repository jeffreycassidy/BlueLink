#.rst:
# FindBluespec
# ------------
#
# Finds the Bluespec compiler and Bluesim simulator

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

IF($ENV{BLUESPECDIR})
	MESSAGE("BLUESPECDIR is present and set to value $ENV{BLUESPECDIR}")
	SET(Bluespec_DIR $ENV{BLUESPECDIR} CACHE PATH "Path to Bluespec lib dir, as typically set during bsc install")
ELSE()
	MESSAGE("BLUESPECDIR is not present - faulty install or environment not set up?")
ENDIF()

IF(NOT Bluespec_FOUND)
	RETURN()
ENDIF()


## Bluespec-specific options
SET(BLUESPEC_VERILOG_SIM_ASSIGNMENT_DELAY "#1" CACHE STRING "Assignment delay to set")

## Bluespec compiler paths
SET(BLUESPEC_BSC_PATH "+" CACHE PATH "Include path for Bluespec")
SET(BLUESPEC_BSC_BDIR "${CMAKE_BINARY_DIR}/bdir" CACHE PATH "Directory for .ba and .bo objects" )
MARK_AS_ADVANCED(BLUESPEC_BSC_BDIR)

## Bluespec compilation options
SET(BLUESPEC_BSC_AGGRESSIVE_CONDITIONS ON CACHE BOOL "-aggressive-conditions switch")
SET(BLUESPEC_BSC_ASSERTIONS ON CACHE BOOL "-check-assert switch")

SET(BLUESPEC_BSC_OPTIONS "" CACHE STRING "Additional compile (sim & verilog) switches not listed above")
SET(BLUESPEC_BSC_SIM_OPTIONS "" CACHE STRING "Additional simulation switches not listed above")
SET(BLUESPEC_BSC_VERILOG_OPTIONS "-opt-undetermined-vals -unspecified-to X" CACHE STRING "Additional Verilog switches not listed above")

MARK_AS_ADVANCED(
	BLUESPEC_BSC_OPTIONS
	BLUESPEC_BSC_SIM_OPTIONS
	BLUESPEC_VERILOG_OPTIONS
)

IF(BLUESPEC_BSC_AGGRESSIVE_CONDITONS)
	SET (BLUESPEC_BSC_OPTIONS "${BLUESPEC_BSC_OPTIONS} -aggressive-conditions")
ENDIF()

IF(BLUESPEC_BSC_ASSERTIONS)
	SET(BLUESPEC_COMPILE_OPTIONS "${BLUESPEC_BSC_OPTIONS} -check-assert")
ENDIF()

SET(BLUESPEC_BSC_SIM_OPTIONS "-sim ${BLUESPEC_BSC_OPTIONS} ${BLUESPEC_BSC_SIM_OPTIONS}")
SET(BLUESPEC_BSC_VERILOG_OPTIONS "-verilog ${BLUESPEC_BSC_OPTIONS} ${BLUESPEC_BSC_VERILOG_OPTIONS}")

FILE(MAKE_DIRECTORY ${BLUESPEC_BSC_BDIR})

## Adds a compilation target for ${FN}.bsv and a target named ${FN}
FUNCTION(ADD_BSV_PACKAGE PACKAGE)

	ADD_CUSTOM_COMMAND(
		OUTPUT ${BLUESPEC_BSC_BDIR}/${PACKAGE}.bo
		COMMAND bsc ${BLUESPEC_COMPILE_OPTS} -p ${BLUESPEC_BSC_PATH} -bdir ${BLUESPEC_BSC_BDIR} ${CMAKE_CURRENT_SOURCE_DIR}/${PACKAGE}.bsv
		DEPENDS ${PACKAGE}.bsv
		WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
		)

	ADD_CUSTOM_TARGET(${PACKAGE} DEPENDS ${BLUESPEC_BSC_BDIR}/${PACKAGE}.bo)
ENDFUNCTION()

## Adds a testbench file from the named package
FUNCTION(ADD_BSV_TESTBENCH PACKAGE)
	ADD_BSV_PACKAGE(${PACKAGE})
ENDFUNCTION()

## Adds a testcase from a previously-added testbench package
## 		Compiles mkTB_${TESTCASE} from package ${PACKAGE}
FUNCTION(ADD_BLUESIM_TESTCASE PACKAGE TESTCASE)
	ADD_CUSTOM_COMMAND(
		OUTPUT ${CMAKE_BINARY_DIR}/test_${TESTCASE}
		COMMAND bsc ${BLUESPEC_BSC_SIM_OPTIONS} -g mkTB_${TESTCASE} -bdir ${BLUESPEC_BSC_BDIR} ${CMAKE_CURRENT_SOURCE_DIR}/${PACKAGE}.bsv 
		COMMAND bsc ${BLUESPEC_BSC_SIM_OPTIONS} -e mkTB_${TESTCASE} -bdir ${BLUESPEC_BSC_BDI} -o ${CMAKE_BINARY_DIR}/test_${TESTCASE}
		DEPENDS ${CMAKE_BINARY_DIR}/${PACKAGE}.bo
		WORKING_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}
	)

## TODO: Add test

	ADD_CUSTOM_TARGET(${TESTCASE} DEPENDS ${PACKAGE} ${CMAKE_BINARY_DIR}/test_${TESTCASE})
ENDFUNCTION()

## Similar to ADD_BLUESIM_TESTCASE above, but generates Verilog code

FUNCTION(ADD_BLUESPEC_VERILOG_TESTCASE PACKAGE TESTCASE)
	MESSAGE("ADD_BLUESPEC_VERILOG_TESTCASE not yet defined but called for package ${PACKAGE} testcase ${TESTCASE}")
ENDFUNCTION()
