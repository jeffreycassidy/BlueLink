## Modelsim setup
IF (VSIM_FOUND)
	SET(VSIM_COMMAND "/usr/local/Altera/14.1/modelsim_ase/bin/vsim" CACHE PATH "path to vsim")
	SET(VLOG_COMMAND "/usr/local/Altera/14.1/modelsim_ase/bin/vlog" CACHE PATH "path to vlog")
	SET(VLIB_COMMAND "/usr/local/Altera/14.1/modelsim_ase/bin/vlib" CACHE PATH "path to vlib")
	SET(VERILOG_TIMESCALE "1ns/1ps" CACHE STRING "Timescale directive for Verilog")
ENDIF()


## Bluespec IP compilation
FILE(GLOB bluespecIP_SRC "$ENV{BLUESPECDIR}/Verilog/*.v")
EXECUTE_PROCESS(
	COMMAND ${VLOG_COMMAND} -work work ${bluespecIP_SRC} -l bluespec.v.log -timescale ${VERILOG_TIMESCALE} ${BLUESPEC_ASSIGNMENT_DELAY_ARG} ${bluespecIP_SRC}
	WORKING_DIRECTORY ${CMAKE_BINARY_DIR})

EXECUTE_PROCESS(COMMAND ${VLIB_COMMAND} work
	WORKING_DIRECTORY ${CMAKE_BINARY_DIR})


#FUNCTION(ADD_VERILOG_SOURCE)
#	ADD_CUSTOM_COMMAND(a
#
#vlog -work <lib> -l <logfile> -timescale 1ns/1ps
#ENDFUNCTION()


FUNCTION(ADD_VERILOG_TESTCASE PACKAGE TESTCASE)
	FILE(MAKE_DIRECTORY ${CMAKE_CURRENT_BINARY_DIR}/VerilogTest)
	ADD_CUSTOM_COMMAND(
		OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/VerilogTest/mkTB_${TESTCASE}.v ${CMAKE_CURRENT_BINARY_DIR}/VerilogTest/mkTB_${TESTCASE}.v.log
		COMMAND bsc -verilog ${BLUESPEC_COMPILE_OPTS} -g mkTB_${TESTCASE} -bdir ${CMAKE_BINARY_DIR} -vdir ${CMAKE_CURRENT_BINARY_DIR}/VerilogTest ${CMAKE_CURRENT_SOURCE_DIR}/${PACKAGE}.bsv
		COMMAND ${VLOG_COMMAND} -work work -l ${CMAKE_CURRENT_BINARY_DIR}/VerilogTest/mkTB_${TESTCASE}.v.log -timescale ${VERILOG_TIMESCALE} ${BLUESPEC_ASSIGNMENT_DELAY_ARG} ${CMAKE_CURRENT_BINARY_DIR}/VerilogTest/mkTB_${TESTCASE}.v
		WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
# Creates the Modelsim script
#		COMMAND bsc -verilog ${BLUESPEC_COMPILE_OPTS} -e mkTB_${TESTCASE}
		DEPENDS ${CMAKE_BINARY_DIR}/${PACKAGE}.bo)

	ADD_TEST(NAME "BSV|${PACKAGE}:mkTB_${TESTCASE}.v"
		COMMAND ${VSIM_COMMAND} -c -do "force CLK -drive 1'b0, 1'b1 @ 2 -repeat 4; force RST_N -drive 1'b0, 1'b1 @ 4; run -all" -t 1ns -lib work -onfinish exit -L altera_mf_ver work.mkTB_${TESTCASE}
		WORKING_DIRECTORY ${CMAKE_BINARY_DIR})
#${VSIM_LIBS})

# vsim -c -do "command" -gGenericName=Value -l logfile -lib <work> -onfinish exit -L <libs> -pli
# -quiet -> suppress loading messages

	ADD_CUSTOM_TARGET(Test_Verilog_${TESTCASE} DEPENDS ${PACKAGE} ${CMAKE_CURRENT_BINARY_DIR}/VerilogTest/mkTB_${TESTCASE}.v)
ENDFUNCTION()


FUNCTION(ADD_VERILOG_SOURCE FNPFX LIB)
	ADD_CUSTOM_COMMAND(
		OUTPUT ${CMAKE_CURRENT_BINARY_DIR}/${FNPFX}.v.log
		COMMAND ${VLOG_COMMAND} -work work -l ${CMAKE_CURRENT_BINARY_DIR}/${FNPFX}.v.log -timescale ${VERILOG_TIMESCALE} ${BLUESPEC_ASSIGNMENT_DELAY_ARG} ${CMAKE_CURRENT_SOURCE_DIR}/${FNPFX}.v
		WORKING_DIRECTORY ${CMAKE_BINARY_DIR}
		DEPENDS ${FNPFX}.v)

	ADD_CUSTOM_TARGET(${FNPFX} DEPENDS ${CMAKE_CURRENT_BINARY_DIR}/${FNPFX}.v.log)
ENDFUNCTION()

