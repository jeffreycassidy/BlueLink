package AlteraM20k;

import BRAMStall::*;


/** Create a dual-port unguarded BRAM with stall capability */

import "BVI" module mkBRAM2Stall#(Integer depth)(BRAM_DUAL_PORT_Stall#(addrT,dataT))
    provisos (
        Bits#(addrT,na),
        Bits#(dataT,nd)
        );

    default_clock(CLK,(*unused*)CLK_GATE);
    no_reset;


    parameter ADDR_WIDTH=valueOf(na);
    parameter DATA_WIDTH=valueOf(nd);
    parameter PIPELINED=1;
    parameter MEMSIZE=depth;

    interface BRAM_PORT_Stall a;
        method putcmd(WEA,ADDRA,DIA) enable (ENA);
        method DOA readdata;
        method deq() enable(DEQA);
    endinterface

    interface BRAM_PORT_Stall b;
        method putcmd(WEB,ADDRB,DIB) enable (ENB);
        method DOB readdata;
        method deq() enable(DEQB);
    endinterface

    schedule (a.putcmd, a.readdata, a.deq) CF (b.putcmd, b.readdata, b.deq);
    schedule a.putcmd CF (a.deq,a.readdata);
    schedule b.putcmd CF (b.deq,b.readdata);

    schedule a.putcmd C a.putcmd;
    schedule b.putcmd C b.putcmd;

    schedule a.readdata CF (a.readdata,a.deq);
    schedule b.readdata CF (b.readdata,b.deq);

    schedule a.deq C a.deq;
    schedule b.deq C b.deq;
endmodule



endpackage
