source capi_sim.tcl

proc com {} {
    vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 MLAB_0l.v
	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 mkSyn_AFUToHost512.v
}

com

simcapi mkSyn_AFUToHost512

add wave -noupdate -divider { AFUToHost512 }

set nTags 16
set nBuf  16

proc serno { i } { 
	if { $i == 0 } { return "" } else { return ${i}_ } }

for { set i 0 } { $i < $nBuf } { incr i } {
	add wave -noupdate -label "Buffer status $i" /top/a0/afurev/dut_streamctrl_bufferFree_[serno $i]rv
}

run 40us
