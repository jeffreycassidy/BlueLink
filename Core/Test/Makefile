test: Test_Parity
	./Test_Parity

# quick terminal-based test of Parity function
Test_Parity: Test_Parity.bsv ../Parity.bo
	bsc -p +:.. -u $<
	bsc -p +:.. -sim -g mkTB $<
	bsc -sim -e mkTB -o $@
