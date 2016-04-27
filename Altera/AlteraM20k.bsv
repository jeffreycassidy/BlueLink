package AlteraM20k;

import BRAMStall::*;


/** Create a dual-port unguarded BRAM with stall capability
 * This shouldn't be used in user code - use the wrapped version below.
 */

import "BVI" module mkBRAM2StallPrimUG#(Integer depth)(BRAM_DUAL_PORT_Stall_PrimUG#(addrT,dataT))
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

    interface BRAM_PORT_Stall_PrimUG a;
        method putcmd(WEA,ADDRA,DIA) enable (ENA);
        method DOA readdata;
        method deq() enable(DEQA);
        method clear() enable(CLRA);
    endinterface

    interface BRAM_PORT_Stall_PrimUG b;
        method putcmd(WEB,ADDRB,DIB) enable (ENB);
        method DOB readdata;
        method deq() enable(DEQB);
        method clear() enable(CLRB);
    endinterface

    schedule (a.putcmd, a.readdata, a.deq) CF (b.putcmd, b.readdata, b.deq);
    schedule a.putcmd CF (a.deq,a.readdata);
    schedule b.putcmd CF (b.deq,b.readdata);

    schedule a.putcmd C a.putcmd;
    schedule b.putcmd C b.putcmd;

    schedule (a.clear,b.clear) CF(a.clear,b.clear,a.putcmd,a.readdata,a.deq,b.putcmd,b.readdata,b.deq);

    schedule a.readdata CF (a.readdata,a.deq);
    schedule b.readdata CF (b.readdata,b.deq);

    schedule a.deq C a.deq;
    schedule b.deq C b.deq;
endmodule


/** 2-port block RAM with input & output registers and the ability to pause the output register.
 * 
 */

module mkBRAM2Stall#(Integer depth)(BRAM2PortStall#(addrT,dataT))
    provisos (
        Bits#(addrT,na),
        Bits#(dataT,nd));
    let _ram <- mkBRAM2StallPrimUG(depth);
    let a <- mkBRAMStallPipeOut(_ram.a);
    let b <- mkBRAMStallPipeOut(_ram.b);

    interface BRAMPortStall porta = a;
    interface BRAMPortStall portb = b;
endmodule

export mkBRAM2Stall;

endpackage
