package Test_HostToAFUBulk;

import AFU::*;
import PSLTypes::*;
import HostToAFUBulk::*;
import Assert::*;
import StmtFSM::*;
import Vector::*;
import PAClib::*;
import ClientServer::*;
import DedicatedAFU::*;
//import Clocks::*;
import AFUHardware::*;

import Common::*;

import CmdBuf::*;

import BDPIPipe::*;

import MMIO::*;

import Reserved::*;

import Endianness::*;

typedef struct {
	LittleEndian#(EAddress64)	eaSrc;
	LittleEndian#(UInt#(64))	size;

    ReservedZero#(512)  padC;
    ReservedZero#(256)  padB;
    ReservedZero#(128)  padA;

} HostToAFUWED deriving(Bits,Eq);

import FIFO::*;

module mkAFU_HostToAFUBulk(Tuple2#(DedicatedAFUNoParity#(2),PipeOut#(Tuple2#(UInt#(16),Bit#(512)))));
    //// WED reg
    SegReg#(HostToAFUWED,2,512) wedreg <- mkSegReg(HostNative,unpack(?));
    HostToAFUWED wed = wedreg.entire;

	Bool verbose=False;

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

    let { streamctrl, istream }  <- mkHostToAFUBulk(8,cmdbuf.client[0],EndianSwap);

    let pwFinish <- mkPulseWire;

    FIFO#(void) ret <- mkFIFO1;

    Stmt ctlstmt = seq
        action
            $display($time," INFO: AFU Master FSM starting");
            $display($time,"      Size:          %016X",wed.eaSrc._payload.addr);
            $display($time,"      Start address: %016X",wed.size._payload);
            streamctrl.start(wed.eaSrc._payload.addr,wed.size._payload);
        endaction
        await(streamctrl.done);
        streamDone <= True;
        $display($time," INFO: AFU Master FSM copy complete");
        await(pwFinish);
        ret.enq(?);
    endseq;

    let ctlfsm <- mkFSMWithPred(ctlstmt,rstfsm.done);


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
                            1:          mmResp.enq(tagged DWordData pack(wed.eaSrc._payload.addr));
                            2:          mmResp.enq(tagged DWordData pack(wed.size._payload));
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

    return tuple2(afu,istream);

endmodule

(* clock_prefix="ha_pclock" *)

module mkSyn_HostToAFUBulk(AFUHardware#(2));
    let { dut, oPipe } <- mkAFU_HostToAFUBulk;
    let wrap <- mkDedicatedAFUNoParity(False,False,dut);

    Bool verbose=True;

	Reg#(File) fd <- mkRegU;

	Stmt ctrl = seq
		action
			let t <- $fopen("HostToAFUBulk.hex","w");
			fd <= t;
		endaction

		repeat(10000) noAction;
	endseq;

	mkAutoFSM(ctrl);

	Reg#(UInt#(32)) p <- mkReg(0);

	rule showOutput;
		oPipe.deq;
		let { addr, data } = oPipe.first;
		if (verbose)
			$display($time,"Output [%04X]: %0128X",addr,data);
		$fdisplay(fd,"%04X %0128X",addr,data);
	endrule

    AFUHardware#(2) hw <- mkCAPIHardwareWrapper(wrap);
    return hw;
endmodule

endpackage
