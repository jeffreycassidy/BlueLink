# 'make all' will provide all the Bluespec Object (.bo) files required

all: PSLTypes.bo PSLInterface.bo SnoopConnection.bo

enums: PSLCommands.bsv PSLControlCommands.bsv PSLJobOpcodes.bsv PSLTranslationOrderings.bsv PSLResponseCodes.bsv

PSLTypes.bo: PSLCommands.bo PSLControlCommands.bo PSLJobOpcodes.bo PSLTranslationOrderings.bo PSLResponseCodes.bo Parity.bo

%.bo: %.bsv
	bsc -p + -u $<

# create a BSV enum file from a list of commands copied from the PDF file
PSL%s.bsv: PSL%s.enum
	perl make_bsv_enum.pl $*

clean:
	rm -f *.o *.so schedule.* transcript vsim.wlf wlft* *.cxx mk*.c mk*.h pseries_nvram.* *.ba *.bo \
    PSLJobOpcodes.bsv PSLResponseCodes.bsv PSLControlCommands.bsv PSLCommands.bsv PSLTranslationOrderings.bsv mkTB.v Test_Parity
