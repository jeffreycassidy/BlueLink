# ModelSim driver script for Memcopy demo, based on CAPI Demo Kit by IBM
# modifications by Jeffrey Cassidy

# com		Compiles all source and sets a BSV assignment delay of 1ns (period is 4ns)
# rs		Re-source the script file
# sim		Run simulation, driving clock on 4ns period and deasserting RST_N for 4ns


proc com {} {
    vlog +define+BSV_ASSIGNMENT_DELAY=\#1 -timescale 1ns/1ns mkMemcopyTB.v \
        ../../PSLVerilog/psl_sim.v ../../PSLVerilog/psl_sim_wrapper.v /usr/local/Bluespec/lib/Verilog/SizedFIFO.v
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
    vsim -pli $afulib mkMemcopyTB -t 1ns

	onfinish stop
	force -drive RST_N 1'b0,1'b1 4
    force -drive -repeat 4ns CLK 1'b0 0,1'b1 2

	run 2us
}
