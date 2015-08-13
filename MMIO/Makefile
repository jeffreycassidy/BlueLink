all: MMIO.bo MMIOConfig.bo

libs: all
	
%.bo: %.bsv
	bsc -p +:../Core -u $<

clean:
	rm -f *.b[ao]
