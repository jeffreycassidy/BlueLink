package Test_AlteraM20kMux;

import ClientServer::*;
import AlteraM20k::*
import GetPut::*;
import PAClib::*;

function Server#(a,b) f_gate_Server(Bool enReq,Bool enResp,Server#(a,b) s) = interface Server;
    interface Put request;
        method Action put(a i) if (enReq) = s.request.put(i);
    endinterface
    interface Get response;
        method ActionValue#(b) get if (enResp) = s.response.get;
    endinterface
endinterface;



interface BRAMTestIfc#(type addrT,type dataT);
    // scan-chain interface
    interface Server#(Tuple2#(addrT,MemRequest#(dataT)),dataT)  scan;

    // client ports
    interface Server#(Tuple2#(addrT,MemRequest#(dataT)),dataT)  a;
    interface Server#(Tuple2#(addrT,MemRequest#(dataT)),dataT)  b;

    // mode control
    method Action scanChainEnable(Bool e);
endinterface


module [Module] mkSyn_M20kPipe8kx512(BRAMTestIfc#(UInt#(16),Bit#(512)));
    // Scan chain enable (disables client port A)
    Reg#(Bool) en <- mkReg(False);

    // The device and its interfaces
    BRAM_DUAL_PORT_Stall#(UInt#(16),Bit#(512)) br <- mkBRAM2Stall(8192);

    let sa <- mkPipe_to_Server(
        mkCompose(
            mkCompose(mkBuffer,
                mkBRAMPortPipeOut(br.a)),
            mkBuffer));

    let sb <- mkPipe_to_Server(
        mkCompose(
            mkCompose(
                mkBuffer,
                mkBRAMPortPipeOut(br.b)),
            mkBuffer));


    // Output servers
    interface Server scan   = f_gate_Server(en,en,sa);
    interface Server a      = f_gate_Server(!en,!en,sa);
    interface Server b      = sb;

    method Action scanChainEnable(Bool e) = en._write(e);
endmodule

endpackage
