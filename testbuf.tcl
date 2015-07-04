proc com {} {
    vlog MLAB_0l.v
    vlog mkTB_AFUReadBuf.v
    vlog mkTB_AFUWriteBuf.v
    vlog mkTB_TagManager.v
	vlog mkTB_StreamManager.v
	vlog mkTB_OStream.v
	vlog /usr/local/Bluespec/lib/Verilog/SizedFIFO.v
}

proc simulate { tbname } {
    vsim -L altera_mf_ver $tbname

    force -drive CLK 1'b0, 1'b1 5 -repeat 10
    force -drive RST_N 1'b0, 1'b1 10
    onfinish stop
    run -all
}

proc simw {} { simulate mkTB_AFUWriteBuf }
proc simr {} { simulate mkTB_AFUReadBuf }

proc simt {} { simulate mkTB_TagManager }

proc simstream {} { simulate mkTB_StreamManager }
proc simostream {} { simulate mkTB_OStream }
