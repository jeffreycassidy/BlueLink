# 'make all' will provide all the Bluespec Object (.bo) files required
# Requires BlueLogic package; may provide the path to it by environment variable BLUELOGIC, or by editing line below

ifndef BLUELOGIC
    BLUELOGIC=/home/jcassidy/Mac/src/BlueLogic
endif

all: PSLTypes.bo PSLInterface.bo SnoopConnection.bo

enums: PSLCommands.bsv PSLControlCommands.bsv PSLJobOpcodes.bsv PSLTranslationOrderings.bsv PSLResponseCodes.bsv

PSLTypes.bo: PSLCommands.bo PSLControlCommands.bo PSLJobOpcodes.bo PSLTranslationOrderings.bo PSLResponseCodes.bo Parity.bo

%.bo: %.bsv
	bsc -p +:$(BLUELOGIC)/Pipeline:$(BLUELOGIC)/Convenience -u $<

# create a BSV enum file from a list of commands copied from the PDF file
PSL%s.bsv: PSL%s.enum
	perl make_bsv_enum.pl $*

clean:
	rm -f *.o *.so schedule.* transcript vsim.wlf wlft* *.cxx mk*.c mk*.h pseries_nvram.* *.ba *.bo \
    PSLJobOpcodes.bsv PSLResponseCodes.bsv PSLControlCommands.bsv PSLCommands.bsv PSLTranslationOrderings.bsv mkTB.v Test_Parity
