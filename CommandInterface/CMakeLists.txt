ADD_BSV_PACKAGE(CmdBuf)
ADD_BSV_PACKAGE(CmdCounter)
ADD_BSV_PACKAGE(ResourceManager)

ADD_DEPENDENCIES(CmdBuf PSLTypes PSLCommands Altera ResourceManager)
ADD_DEPENDENCIES(CmdCounter PSLTypes PSLCommands Altera)
ADD_DEPENDENCIES(ResourceManager Core)

ADD_BSV_TESTBENCH(Test_CmdBuf)
