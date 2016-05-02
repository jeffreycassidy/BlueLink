package BRAMBank;

import Assert::*;
import Vector::*;
import PAClib::*;

interface Switch#(type ifc,type idx);
    method Action   nextCycleSelect(idx i);
    interface ifc   selected;
endinterface

typeclass Switchable#(type ifc);
    module mkSwitch#(Integer init,Vector#(n,ifc) inputs)(Switch#(ifc,UInt#(nbIdx)))
        provisos (Log#(n,nbIdx));
endtypeclass

function Vector#(n,Bool) decode(UInt#(nb) i)
    provisos (Log#(n,nb));
    Vector#(n,Bool) v = replicate(False);
    v[i] = True;
    return v;
endfunction

instance Switchable#(PipeOut#(t));
    module mkSwitch#(Integer init,Vector#(n,PipeOut#(t)) inputs)(Switch#(PipeOut#(t),UInt#(nbIdx)))
        provisos (Log#(n,nbIdx));

        // selection registers
        Reg#(UInt#(nbIdx))              sel <- mkReg(fromInteger(init));
        Reg#(Vector#(n,Bool))     oneHotSel <- mkReg(decode(fromInteger(init)));

        let pwDeq <- mkPulseWire;

        // cheapest implementation for notEmpty: log(n) select bits + n notEmpty (one-hot is n selects + n notEmpty)
        Bool ne = inputs[sel].notEmpty;

        // cheapest implementation for first: standard mux
        // requires -aggressive-conditions to work!
        t firstVal = inputs[sel].first;

        // cheaper implementation is one-hot for deq
        for(Integer i=0;i<valueOf(n);i=i+1)
            (* fire_when_enabled *)
            rule doDeq if (oneHotSel[i] && pwDeq);
                inputs[i].deq;
            endrule

        // allow updates to happen at end of cycle (config reg should permit this, but doesn't for some reason??)
        // when using ConfigReg, placing the reg writes in nextCycleSelect method caused conflict (doDeq failed to fire)
        Wire#(UInt#(nbIdx)) nextCycle <- mkWire;
        rule updateNextCycle;
            oneHotSel   <= decode(nextCycle);
            sel         <= nextCycle;
        endrule

        method Action nextCycleSelect(UInt#(nbIdx) i) = nextCycle._write(i);

        interface PipeOut selected;
            method Bool notEmpty = ne;
            method Action deq if (ne) = pwDeq.send;     // use pulsewire to eliminate implicit conditions
            method first if (ne) = firstVal;
        endinterface
    endmodule
endinstance

//typedef function Tuple2#(UInt#(nbBank),UInt#(nbOffs)) f(UInt#(nbAddr) addr) provisos (Add#(nbBank,nbOffs,nbAddr)) addressSplitFunction;
//
//module mkBRAMDecode(addressSplitFunction f,Vector#(nBRAM,BRAMPortStall#(UInt#(nbOffs),dataT)))
//    (BRAMPortStall#(UInt#(nbAddr),dataT))
//    provisos (
//        
//
//    method Action clear = mapM_(doClear, br);
//    method Action putcmd(Bool wr,UInt#(nbAddr) addr,dataT data);
//    endmethod
//endmodule
//
//module mkBRAMIReg(BRAMPortStall#(addrT,dataT))
//    provisos (
//        Bits#(addrT,na),
//        Bits#(dataT,nd));
//
//    mkLFIFOF
//endmodule
//
//module mkBRAMOReg#(BRAMPortStall#(addrT,dataT))(BRAMPortStall#(addrT,dataT));
//    provisos (
//        Bits#(addrT,na),
//        Bits#(dataT,nd));
//
//    interface BRAMPortStall;
//    endinterface
//endmodule

endpackage
