source capi_sim.tcl

proc com {} {
	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 mkSyn_Memcopy2.v
}

com

simcapi mkSyn_Memcopy2
