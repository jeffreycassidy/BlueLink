package Test_HostToAFUStream;

import AFU::*;
import PSLTypes::*;
import HostToAFUStream::*;
import Assert::*;
import StmtFSM::*;
import Vector::*;
import PAClib::*;
import ClientServer::*;
import DedicatedAFU::*;
import Clocks::*;
import AFUHardware::*;

import Common::*;

import CmdBuf::*;

import BDPIPipe::*;

import MMIO::*;

import Reserved::*;

import Endianness::*;

/** Define WED for EndianSwap (big-endian) cache line ordering; no endian swap needed for each element, but struct elements appear
 * reversed in BSV code vs C/C++
 */

typedef struct {
    ReservedZero#(512)  padC;
    ReservedZero#(256)  padB;
    ReservedZero#(128)  padA;


    EAddress64        size;
    EAddress64        eaSrc;
} HostToAFUWED deriving(Bits,Eq);

import FIFO::*;

module mkAFU_HostToAFUStream(Tuple2#(DedicatedAFUNoParity#(2),PipeOut#(UInt#(64))));
    //// WED reg
    SegReg#(HostToAFUWED,2,512) wedreg <- mkSegReg(EndianSwap,unpack(?));
    HostToAFUWED wed = wedreg.entire;

    Reg#(Bool) streamDone <- mkReg(False);



    //// Reset controller

    Stmt rststmt = seq
        noAction;
        streamDone <= False;
        $display($time," INFO: AFU Reset FSM completed");
    endseq;
    
    FSM rstfsm <- mkFSM(rststmt);



	//// Command buffer

	CacheCmdBuf#(1,2) cmdbuf <- mkCmdBuf(8);





    //// Host -> AFU stream controller

    let { streamctrl, istream }  <- mkHostToAFUStream(4,cmdbuf.client[0],EndianSwap);

    let pwFinish <- mkPulseWire;

    FIFO#(void) ret <- mkFIFO1;

    Stmt ctlstmt = seq
        action
            $display($time," INFO: AFU Master FSM starting");
            $display($time,"      Size:          %016X",wed.eaSrc.addr);
            $display($time,"      Start address: %016X",wed.size.addr);
            streamctrl.start(wed.eaSrc.addr,wed.size.addr);
        endaction
        await(streamctrl.done);
        streamDone <= True;
        $display($time," INFO: AFU Master FSM copy complete");
        await(pwFinish);
        ret.enq(?);
    endseq;

    let ctlfsm <- mkFSMWithPred(ctlstmt,rstfsm.done);



    //// Stream consumer
    
    PipeOut#(Vector#(16,Bit#(64))) t <- mkFn_to_Pipe(unpack,istream);

    // funnel yields right (low-index) bits first
    // in EndianSwap mode, low index <-> low address
    PipeOut#(Vector#(1,Bit#(64))) oFun <- mkFunnel(t);

    PipeOut#(UInt#(64)) o <- mkFn_to_Pipe(compose(unpack,pack),oFun);

	let cmdbufu <- mkClientUFromClient(cmdbuf.psl);

    //// Command interface checking

    FIFO#(MMIOResponse) mmResp <- mkFIFO1;

    DedicatedAFUNoParity#(2) afu = interface DedicatedAFUNoParity
    
        interface Vector wedwrite = map(regToWriteOnly,wedreg.seg);
    
        interface ClientU command = cmdbufu;
    
        interface AFUBufferInterface buffer = cmdbuf.pslbuff;
    
        interface Server mmio;
            interface Get response = toGet(mmResp);
    
            interface Put request;
                method Action put (MMIORWRequest i);
                    if (i matches tagged DWordWrite { index: .dwi, data: .dwd })
                    begin
                        case (dwi) matches
                            5: pwFinish.send;
                            default: noAction;
                        endcase
    
                        mmResp.enq(WriteAck);
                    end
                    else if (i matches tagged DWordRead { index: .dwi })
                        case (dwi) matches
                            0:          mmResp.enq(tagged DWordData 64'h0123456700f00d00);
                            1:          mmResp.enq(tagged DWordData pack(wed.eaSrc.addr));
                            2:          mmResp.enq(tagged DWordData pack(wed.size.addr));
                            3:          mmResp.enq(tagged DWordData (streamDone ? 64'h1111111111111111 : 64'h0));
                            default:    mmResp.enq(tagged DWordData 0);
                        endcase
                    else
                        mmResp.enq(WriteAck);           // just ack word read/write
                endmethod
            endinterface
    
        endinterface
    
        method Action parity_error_jobcontrol   = noAction;
        method Action parity_error_bufferread   = noAction;
        method Action parity_error_bufferwrite  = noAction;
        method Action parity_error_mmio         = noAction;
        method Action parity_error_response     = noAction;
    
        method Action start if (rstfsm.done);
            ctlfsm.start;
        endmethod
    
        method ActionValue#(AFUReturn) retval;
            ret.deq;
            return Done;
        endmethod
    
        interface FSM rst = rstfsm;

    endinterface;

    return tuple2(afu,o);

endmodule

(* clock_prefix="ha_pclock" *)

module mkSyn_HostToAFU(AFUHardware#(2));
    let { dut, oPipe } <- mkAFU_HostToAFUStream;
    let wrap <- mkDedicatedAFUNoParity(False,False,dut);

	Reg#(UInt#(32)) p <- mkReg(0);

	rule showOutput;
		oPipe.deq;
		$display($time,"Output [%08X]: %016X",p,oPipe.first);
		p <= p+8;
	endrule

    AFUHardware#(2) hw <- mkCAPIHardwareWrapper(wrap);
    return hw;
endmodule

endpackage
