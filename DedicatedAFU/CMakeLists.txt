IF(USE_BLUESPEC)
    ADD_BSV_PACKAGE(DedicatedAFU AFU MMIO MMIOConfig Endianness PSLTypes)
    ADD_BSV_PACKAGE(BlockMapAFU DedicatedAFU ReadStream WriteStream CmdArbiter Stream)
ENDIF()
