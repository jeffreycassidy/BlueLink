# 'make all' will provide all the Bluespec Object (.bo) files required

ENUMFILES=PSLJobOpcodes PSLResponseCodes PSLControlCommands PSLCommands PSLTranslationOrderings

all: PSLTypes.bo AFUHardware.bo ClientServerU.bo $(foreach e, $(ENUMFILES), $e.bo) Parity.bo

libs: all

PSLTypes.bo: PSLCommands.bo PSLControlCommands.bo PSLJobOpcodes.bo PSLTranslationOrderings.bo PSLResponseCodes.bo Parity.bo

%.bo: %.bsv
	bsc -p + -u $<

# create a BSV enum file from a list of commands copied from the PDF file
PSL%s.bsv: PSL%s.enum
	perl make_bsv_enum.pl $*

clean:
	rm -f *.o *.so schedule.* transcript vsim.wlf model_*.h model_*.cxx wlft* *.cxx mk*.[chv] pseries_nvram.* *.b[ao] \
	$(foreach e, $(ENUMFILES), $e.bsv $e.h) \
	Test_Parity a.out
