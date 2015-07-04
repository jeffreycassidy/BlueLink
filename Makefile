default: check-OStream

check-OStream: mkTB_OStream.v
	vsim -c -do "source testbuf.tcl; vlog $<; simostream"

check-CAPIStream: mkTB_StreamManager.v
	vsim -c -do "source testbuf.tcl; vlog $<; simstream "	

mkTB_StreamManager.v: CAPIStream.bsv ReadBuf.bsv
	bsc -p +:Core:../BlueLogic/Convenience:../BlueLogic/Pipeline -u $<
	bsc -p +:Core:../BlueLogic/Convenience:../BlueLogic/Pipeline -verilog -g mkTB_StreamManager $<

mkTB_OStream.v: CAPIStream.bsv ReadBuf.bsv
	bsc -p +:Core:../BlueLogic/Convenience:../BlueLogic/Pipeline -u $<
	bsc -p +:Core:../BlueLogic/Convenience:../BlueLogic/Pipeline -verilog -g mkTB_OStream $<
	
