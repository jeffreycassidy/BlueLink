source capi_sim.tcl

proc com {} {
	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 mkSyn_HostToAFUBulk.v
}

com

simcapi mkSyn_HostToAFUBulk

run 8us
