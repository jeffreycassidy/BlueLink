source capi_sim.tcl

proc com {} {
    vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 MLAB_0l.v
	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 mkSyn_RefRefHost.v
}

com

simcapi mkSyn_RefRefHost
