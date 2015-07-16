set CAPI_SL /home/parallels/src/CAPI/pslse/pslse/afu_driver/src/afu_driver.sl

set CAPI_ROOT /home/parallels/src/BlueLink/PSLVerilog/

proc com {} {
	global CAPI_ROOT
    vlog MLAB_0l.v
    vlog mkTB_AFUReadBuf.v
    vlog mkTB_AFUWriteBuf.v
#    vlog mkTB_TagManager.v
	vlog mkTB_StreamManager.v
	vlog mkTB_OStream.v
	vlog PSLVerilog/mkPOR.v
	vlog -timescale 1ns/1ps mkSyn_StreamManager.v
	vlog $CAPI_ROOT/psl_sim.v $CAPI_ROOT/psl_sim_wrapper.v $CAPI_ROOT/pslse_top.v
	vlog /usr/local/Bluespec/lib/Verilog/FIFO2.v
	vlog /usr/local/Bluespec/lib/Verilog/FIFO1.v
	vlog /usr/local/Bluespec/lib/Verilog/FIFO10.v
	vlog /usr/local/Bluespec/lib/Verilog/SizedFIFO.v
	vlog /usr/local/Bluespec/lib/Verilog/MakeReset0.v
	vlog /usr/local/Bluespec/lib/Verilog/SyncReset.v
}

proc simulate { tbname } {
    vsim -L altera_mf_ver $tbname

    force -drive CLK 1'b0, 1'b1 5 -repeat 10
    force -drive RST_N 1'b0, 1'b1 10
    onfinish stop
    run -all
}

proc simcapi { tbname } {
	global CAPI_SL CAPI_ROOT

# Compile psl sim toplevel with the DUT name inserted
#	log -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 +define+DUTMODULETYPE=$tbname $CAPI_ROOT/revwrap.v
#	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 +define+DUTMODULETYPE=$tbname $CAPI_ROOT/pslse_top.v

	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+DUTMODULETYPE=$tbname $CAPI_ROOT/revwrap.v
	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+DUTMODULETYPE=$tbname $CAPI_ROOT/pslse_top.v
	
	
	
	
	vsim -t 1ns -L altera_mf_ver -pli $CAPI_SL top

	add wave -noupdate -divider "Clock"
	add wave -noupdate ha_pclock
	add wave -noupdate -divider "Reset generation"
	add wave -noupdate {top/a0/afurev/rstctrl$OUT_RST}

	add wave -noupdate -divider "AFU Control"
	add wave -noupdate ha_jval
	add wave -noupdate -radix hexadecimal ha_jcom
	add wave -noupdate -radix hexadecimal ha_jea

	add wave -noupdate -divider "AFU Status"
	add wave -noupdate ah_jrunning
	add wave -noupdate ah_jdone
	add wave -noupdate -radix hexadecimal ah_jerror


	add wave -noupdate -divider "MMIO"
	add wave -noupdate -divider "Input"
	add wave -noupdate ha_mmval
	add wave -noupdate -radix hexadecimal ha_mmdata
	add wave -noupdate -radix hexadecimal ha_mmad

	add wave -noupdate -divider "Output"
	add wave -noupdate ah_mmack
	add wave -noupdate -radix hexadecimal ah_mmdata

#    force -drive ha_pclock 1'b0, 1'b1 2 -repeat 4
    onfinish stop
    run 500ns
}

proc rs {} { source testbuf.tcl }

proc simw {} { simulate mkTB_AFUWriteBuf }
proc simr {} { simulate mkTB_AFUReadBuf }

proc simt {} { simulate mkTB_TagManager }

proc simstream {} { simulate mkTB_StreamManager }
proc simostream {} { simulate mkTB_OStream }
