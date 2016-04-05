source capi_env.tcl
source capi_waves.tcl

proc simcapi { tbname } {
	global BLUELINK PSLSE_DRIVER_LIB

    # Compile IBM toplevel (modified so HA_ASSIGNMENT_DELAY sets a delay on all register assignments)
	vlog -timescale 1ns/1ns +define+HA_ASSIGNMENT_DELAY=\#1 $BLUELINK/PSLVerilog/top.v

    # Compile bit-reverse wrapper with the correct toplevel name
    # Required to correctly match bit order from PSLSE (0:N-1) with Bluespec (N-1:0)
    # Also provides power-on reset required for BSV
    vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+HA_ASSIGNMENT_DELAY=\#1 +define+BSV_ASSIGNMENT_DELAY=\#1 +define+DUTMODULETYPE=$tbname $BLUELINK/PSLVerilog/revwrap.v

# Launch sim
	vsim -t 1ns -L altera_mf_ver -L vsim_bluelink -L bsvlibs -pli $PSLSE_DRIVER_LIB top

	add wave -noupdate /top/a0/afurev/ha_pclock
	add wave -noupdate top/a0/afurev/RST_N

# Setup up the waveform viewer

# global var required by wave_capi for buffer read valid delay
	set brlatcycles 2
    wave_capi /

    onfinish stop
}
