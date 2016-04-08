IF(Bluespec_FOUND)
    ADD_BSV_PACKAGE(AlteraM20k)
    ADD_BSV_PACKAGE(ProgrammableLUT)
    ADD_DEPENDENCIES(AlteraM20k BRAMStall)
ENDIF()

ADD_CUSTOM_TARGET(Altera DEPENDS AlteraM20k ProgrammableLUT)


## TODO: Need an automated way to rebuild this lib when .v files change

EXECUTE_PROCESS(
    COMMAND ${VSIM_VLIB_EXECUTABLE} bsvaltera
    COMMAND ${VSIM_VLOG_EXECUTABLE} ${BLUESPEC_VERILOG_LIB_OPTS} -work bsvaltera ${CMAKE_CURRENT_SOURCE_DIR}/MLAB_0l.v
    WORKING_DIRECTORY ${CMAKE_BINARY_DIR}

    )
