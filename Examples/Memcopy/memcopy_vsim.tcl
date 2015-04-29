# ModelSim driver script for Memcopy demo, based on CAPI Demo Kit by IBM
# modifications by Jeffrey Cassidy

# com		Compiles all source and sets a BSV assignment delay of 1ns (period is 4ns)
# rs		Re-source the script file
# sim		Run simulation, driving clock on 4ns period and deasserting RST_N for 4ns

proc com {} {
	global env
    vlog +define+BSV_ASSIGNMENT_DELAY=\#1 -timescale 1ns/1ns mkMemcopyTB.v mkMemcopyAFU.v \
        ../../PSLVerilog/psl_sim.v ../../PSLVerilog/psl_sim_wrapper.v $env(BLUESPECDIR)/Verilog/SizedFIFO.v $env(BLUESPECDIR)/Verilog/SizedFIFO0.v $env(BLUESPECDIR)/Verilog/FIFO1.v $env(BLUESPECDIR)/Verilog/FIFO2.v
}

proc rs {} {
    source memcopy_vsim.tcl
}

if { [info exists env(CAPI_AFU_DRIVER)] == 1 } {
	set afulib $env(CAPI_AFU_DRIVER) } else {
	set afulib ./afu_driver.sl
	puts "CAPI_AFU_DRIVER environment variable not set; assuming afu_driver.sl in current working dir"
}

puts "afulib = $afulib"

proc sim {} {
    global afulib
    com
    vsim -pli $afulib top -t 1ns

	onfinish stop
	force -drive -freeze a0/RST_N 1'b0 -cancel @4
#a    	force -drive -repeat 4ns CLK 1'b0 0,1'b1 2
}

proc waves {} {
	add wave -noupdate ha_pclock
	add wave -noupdate a0/RST_N
}
