ADD_BSV_PACKAGE(CmdTagManager PSLTypes AFU ResourceManager ClientServerU)
ADD_BSV_PACKAGE(Stream PSLTypes CmdTagManager)

ADD_BSV_PACKAGE(ReadStream Stream ProgrammableLUT)
ADD_BSV_PACKAGE(WriteStream Stream ProgrammableLUT)
ADD_BSV_PACKAGE(CmdArbiter CmdTagManager)

ADD_BSV_TESTBENCH(Test_ReadStream)
