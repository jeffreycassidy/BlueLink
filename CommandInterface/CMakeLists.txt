IF(USE_BLUESPEC)
    #ADD_BSV_PACKAGE(CmdBuf PSLTypes PSLCommands Altera ResourceManager)
    #ADD_BSV_PACKAGE(CmdCounter PSLTypes PSLCommands)
    ADD_BSV_PACKAGE(ResourceManager ProgrammableLUT)

    #ADD_BSV_TESTBENCH(Test_CmdBuf)

ENDIF()
