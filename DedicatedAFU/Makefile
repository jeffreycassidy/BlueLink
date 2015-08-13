all: libs

libs: DedicatedAFU.bo

DedicatedAFU.bo: DedicatedAFU.bsv
	bsc -p +:../Core:../MMIO -u $<

clean:
	rm -f *.b[ao]
