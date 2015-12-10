source /home/jcassidy/src/BlueLink/capi_waves.tcl

vlog -timescale 1ns/1ps +define+BSV_ASSIGNMENT_DELAY=#1 +define+BSV_NO_INITIAL_BLOCKS -work work $env(BLUESPECDIR)/Verilog/FIFO*.v $env(BLUESPECDIR)/Verilog/RWire.v $env(BLUESPECDIR)/Verilog/RWire0.v ../../Altera/BRAM2.Stall.v $env(BLUESPECDIR)/Verilog/Counter.v $env(BLUESPECDIR)/Verilog/SizedFIFO.v

vlog -timescale 1ns/1ps +define+BSV_ASSIGNMENT_DELAY=#1 +define+BSV_NO_INITIAL_BLOCKS -work work mkSyn_MemLoad.v
vlog -timescale 1ns/1ps +define+HA_ASSIGNMENT_DELAY=#1 $env(BLUELINK)/BlueLink/PSLVerilog/top.v
vlog -timescale 1ns/1ps +define+DUTMODULETYPE=mkSyn_MemLoad $env(BLUELINK)/BlueLink/PSLVerilog/revwrap.v

vsim top -L altera_mf_ver -L vsim_bluelink -pli $env(PSLSE_DRIVER_LIB)

add wave -noupdate ha_pclock
wave_capi /

run -all
