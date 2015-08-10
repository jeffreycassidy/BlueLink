set CAPI_SL /home/parallels/src/CAPI/pslse/afu_driver/src/veriuser.sl

set CAPI_ROOT /home/parallels/src/BlueLink/PSLVerilog/

proc com {} {
	global CAPI_ROOT
#    vlog mkTB_TagManager.v

    vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 MLAB_0l.v
    vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 mkTB_AFUReadBuf.v
    vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 mkTB_AFUWriteBuf.v
	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 mkTB_OStream.v


	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 mkSyn_AFUToHost.v
	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 mkSyn_HostToAFU.v


    vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 /usr/local/Bluespec/lib/Verilog/FIFO2.v
	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 /usr/local/Bluespec/lib/Verilog/FIFO1.v
	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 /usr/local/Bluespec/lib/Verilog/FIFO10.v
	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 /usr/local/Bluespec/lib/Verilog/SizedFIFO.v
	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 /usr/local/Bluespec/lib/Verilog/MakeReset0.v
	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 /usr/local/Bluespec/lib/Verilog/SyncReset.v
	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+BSV_ASSIGNMENT_DELAY=\#1 /usr/local/Bluespec/lib/Verilog/RevertReg.v
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

	vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+HA_ASSIGNMENT_DELAY=\#1 +define+BSV_ASSIGNMENT_DELAY=\#1 +define+DUTMODULETYPE=$tbname $CAPI_ROOT/top.v
    vlog -timescale 1ns/1ns +define+BSV_NO_INITIAL_BLOCKS +define+HA_ASSIGNMENT_DELAY=\#1 +define+BSV_ASSIGNMENT_DELAY=\#1 +define+DUTMODULETYPE=$tbname $CAPI_ROOT/revwrap.v

	vsim -t 1ns -L altera_mf_ver -pli $CAPI_SL -pli libBDPIPipe32_VPI.so top

# note clock is inverted wrt /top to show assignment delays
	add wave -noupdate /top/a0/afurev/ha_pclock
#	add wave -group Control -noupdate -divider "Reset generation"
	add wave -group Control -noupdate top/a0/afurev/RST_N

	add wave -group Control -noupdate -divider "AFU Control"
	add wave -group Control -noupdate ha_jval
	add wave -group Control -noupdate -radix hexadecimal ha_jcom
    add wave -group Control -noupdate ha_jcompar
	add wave -group Control -noupdate -radix hexadecimal ha_jea
    add wave -group Control -noupdate ha_jeapar

	add wave -group Status -noupdate ah_jrunning
	add wave -group Status -noupdate ah_jdone
	add wave -group Status -noupdate ah_jcack
	add wave -group Status -noupdate ah_tbreq
	add wave -group Status -noupdate ah_paren
	add wave -group Status -noupdate ah_jyield
	add wave -group Status -noupdate -radix hexadecimal ah_jerror

    add wave -group Command -group Request ah_cvalid
    add wave -group Command -group Request -radix hexadecimal ah_com
    add wave -group Command -group Request ah_compar
    add wave -group Command -group Request -radix hexadecimal ah_ctag
    add wave -group Command -group Request ah_ctagpar
    add wave -group Command -group Request -radix hexadecimal ah_cabt
    add wave -group Command -group Request -radix hexadecimal ah_csize
    add wave -group Command -group Request -radix hexadecimal ah_cea
    add wave -group Command -group Request ah_ceapar
    add wave -group Command -group Request -radix hexadecimal ah_cch

    add wave -group Command -group Response ha_rvalid
    add wave -group Command -group Response -radix hexadecimal ha_rtag
    add wave -group Command -group Response ha_rtagpar
    add wave -group Command -group Response -radix hexadecimal ha_response
    add wave -group Command -group Response -radix signed ha_rcredits
    add wave -group Command -group Response -radix hexadecimal ha_rcachestate
    add wave -group Command -group Response -radix hexadecimal ha_rcachepos



# MMIO
#   Request
	add wave -group MMIO -group Request -noupdate ha_mmval
	add wave -group MMIO -group Request -noupdate ha_mmcfg
	add wave -group MMIO -group Request -noupdate ha_mmrnw
	add wave -group MMIO -group Request -noupdate -radix hexadecimal ha_mmdata
	add wave -group MMIO -group Request -noupdate -radix hexadecimal ha_mmad

#   ConfigSpace
    add wave -group MMIO -group ConfigSpace -noupdate -radix hexadecimal -label D_IN_TAG  {top/a0/afurev/wrap_mmCfg_o/D_IN[65:64]}
    add wave -group MMIO -group ConfigSpace -noupdate -radix hexadecimal -label D_IN_DATA {top/a0/afurev/wrap_mmCfg_o/D_IN[63:0]}
    add wave -group MMIO -group ConfigSpace -noupdate top/a0/afurev/wrap_mmCfg_o/ENQ
    add wave -group MMIO -group ConfigSpace -noupdate top/a0/afurev/wrap_mmCfg_o/DEQ
    add wave -group MMIO -group ConfigSpace -noupdate top/a0/afurev/wrap_mmCfg_o/FULL_N
    add wave -group MMIO -group ConfigSpace -noupdate top/a0/afurev/wrap_mmCfg_o/EMPTY_N
    add wave -group MMIO -group ConfigSpace -noupdate top/a0/afurev/wrap_mmCfg_o/D_OUT

#   Response
	add wave -group MMIO -group Response -noupdate ah_mmack
	add wave -group MMIO -group Response -noupdate -radix hexadecimal ah_mmdata
	add wave -group MMIO -group Response -noupdate ah_mmdatapar


# Buffer
#   Read
#       Request
    add wave -group Buffer -group Read -group Request -noupdate ha_brvalid
    add wave -group Buffer -group Read -group Request -noupdate -radix unsigned ha_brtag
    add wave -group Buffer -group Read -group Request -noupdate ha_brtagpar
    add wave -group Buffer -group Read -group Request -noupdate -radix unsigned ha_brad

#       Response
    add wave -group Buffer -group Read -group Response -noupdate -radix hexadecimal ah_brdata
    add wave -group Buffer -group Read -group Response -noupdate -radix hexadecimal ah_brpar

    add wave -group Buffer -group Read -group Response -noupdate -radix unsigned ah_brlat

    add wave -group Buffer -group Read -group Response -noupdate -radix hexadecimal ah_brpar

#       Read testbench
    add wave -group Buffer -group Read -group Testbench -noupdate -radix hexadecimal brdata_delay
    add wave -group Buffer -group Read -group Testbench -noupdate -radix hexadecimal brvalid_delay

#   Write
    add wave -group Buffer -group Write -noupdate ha_bwvalid
    add wave -group Buffer -group Write -noupdate -radix unsigned ha_bwtag
    add wave -group Buffer -group Write -noupdate ha_bwtagpar
    add wave -group Buffer -group Write -noupdate -radix hexadecimal ha_bwad
    add wave -group Buffer -group Write -noupdate -radix hexadecimal ha_bwdata
    add wave -group Buffer -group Write -noupdate -radix hexadecimal ha_bwpar

#    add wave -noupdate -divider "Stream manager"
#    add wave -noupdate {top/a0/afurev/streamctrl_mgr_pwClr_0$whas}
#    add wave -noupdate {top/a0/afurev/streamctrl_mgr_pwClr_1$whas}
#    add wave -noupdate {top/a0/afurev/streamctrl_mgr_pwClr_2$whas}
#    add wave -noupdate {top/a0/afurev/streamctrl_mgr_pwClr_3$whas}
#
#    add wave -noupdate {top/a0/afurev/streamctrl_mgr_avail_0}
#    add wave -noupdate {top/a0/afurev/streamctrl_mgr_avail_1}
#    add wave -noupdate {top/a0/afurev/streamctrl_mgr_avail_2}
#    add wave -noupdate {top/a0/afurev/streamctrl_mgr_avail_3}

    onfinish stop

    run -all
}

proc rs {} { source testbuf.tcl }

proc simw {} { simulate mkTB_AFUWriteBuf }
proc simr {} { simulate mkTB_AFUReadBuf }

proc simt {} { simulate mkTB_TagManager }

proc simafu2host {} { simcapi mkSyn_AFUToHost }

proc simstream {} { simulate mkTB_StreamManager }
proc simostream {} { simcapi }
