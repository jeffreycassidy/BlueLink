package AFUToHostStream;

import BuildVector::*;

import Common::*;

import Assert::*;
import AFU::*;
import PSLTypes::*;
import FIFO::*;
import PAClib::*;
import Vector::*;
import StmtFSM::*;
import MMIO::*;
import Clocks::*;
import DedicatedAFU::*;
import AFUHardware::*;
import Reserved::*;
import BDPIPipe::*;

import CmdBuf::*;
import WriteBuf::*;

import Cntrs::*;
import Counter::*;

import ShiftRegUnfunnel::*;

import TagManager::*;

import ReadBuf::*;

typedef struct { UInt#(64) addr; } EAddress64LE deriving(Eq);

function Bit#(n) endianSwap(Bit#(n) i) provisos (Mul#(nbytes,8,n),Div#(n,8,nbytes),Log#(nbytes,k));
    Vector#(nbytes,Bit#(8)) t = toChunks(i);
    return pack(reverse(t));
endfunction

instance Bits#(EAddress64LE,64);
    function Bit#(64) pack(EAddress64LE i) = endianSwap(pack(i.addr));
    function EAddress64LE unpack(Bit#(64) b) = EAddress64LE { addr: unpack(endianSwap(b)) };
endinstance

typedef struct {
    EAddress64LE        eaDst;
    EAddress64LE        size;

    ReservedZero#(128)  padA;

    ReservedZero#(256)  padB;



    ReservedZero#(512)  padC;
} AFUToHostWED deriving(Bits,Eq);

interface AFUToHostStream;
    // start the stream
    method Action start(UInt#(64) ea,UInt#(64) size);
    method Bool done;
endinterface




/** Sinks a stream to host memory.
 *
 * The user starts the transfer by providing an address and a size, then is able to push (size) bytes to the host in 1024b chunks.
 *
 * Currently requires cache-aligned ea and size. 
 */

module mkAFUToHostStream#(CmdBufClientPort#(2) cmdbuf,PipeOut#(Bit#(1024)) pi)(AFUToHostStream)
    provisos (
        NumAlias#(nt,4));

    Integer stepBytes=128;
    Integer alignBytes=stepBytes;

    Reg#(UInt#(64)) eaStart   <- mkReg(0);
    Reg#(UInt#(64)) ea        <- mkReg(0);
    Reg#(UInt#(64)) eaEnd     <- mkReg(0);

    WriteBuf#(2) wbuf <- mkAFUWriteBuf(16);

    mkConnection(cmdbuf.buffer.writedata,wbuf.pslin);

    Cntrs::Count#(UInt#(8)) outstanding <- mkCount(0);


    // implicit conditions: value available from PipeOut
    rule doWriteCommand if (ea != eaEnd);
        // send command and get tag
        let cmd = CmdWithoutTag {
            com: Write_mi,
            cabt: Abort,
            cea: EAddress64 { addr: ea },
            csize: fromInteger(stepBytes) };
        let tag <- cmdbuf.putcmd(cmd);

        // write data to buffer
        wbuf.write(tag,pi.first);
        pi.deq;

        // bump write pointer
        ea <= ea + fromInteger(stepBytes);
        outstanding.incr(1);
    endrule

    rule handleResponse;
        let resp <- cmdbuf.response.get;

        case (resp.response) matches
            Done:
                $display($time," Write completion for tag %X",resp.rtag);
   	        Paged:
                $display($time," WARNING: PAGED response ignored for tag %X",resp.rtag);
           
            default:
                action
                    $display($time,"ERROR: Invalid command code received ",fshow(resp));
                    dynamicAssert(False,"Invalid command code received");
                endaction
        endcase

        outstanding.decr(1);
    endrule

    method Action start(UInt#(64) ea0,UInt#(64) size);
        eaStart <= ea0;
        ea <= ea0;
        eaEnd <= ea0+size;

        outstanding <= 0;

        dynamicAssert(ea0 % fromInteger(alignBytes) == 0,    "Effective address is not properly aligned");
        dynamicAssert(size % fromInteger(alignBytes) == 0,   "Transfer size is not properly aligned");
    endmethod

    method Bool done = ea==eaEnd && outstanding == 0;
endmodule





module mkAFU_AFUToHostStream#(PipeOut#(Bit#(32)) pi)(DedicatedAFUNoParity#(AFUToHostWED,2));
    //// WED reg
    SegReg#(AFUToHostWED,2,512) wed <- mkSegReg(unpack(?));



    //// Reset controller

    Stmt rststmt = seq
        noAction;
        $display($time," INFO: AFU Reset FSM completed");
    endseq;
    
    FSM rstfsm <- mkFSM(rststmt);



    PipeOut#(Bit#(1024)) stream <- mkShiftRegUnfunnel(Left,pi);

    CacheCmdBuf#(1,2) cmdbuf <- mkCmdBuf(4);


    //// Host -> AFU stream controller

    let pwStart <- mkPulseWire;
    let pwFinish <- mkPulseWire;

    let streamctrl <- mkAFUToHostStream(cmdbuf.client[0],stream);

    FIFO#(void) ret <- mkFIFO1;

    Reg#(Bool) streamDone <- mkReg(False);
    Reg#(Bool) masterDone <- mkReg(False);

    Stmt ctlstmt = seq
        masterDone <= False;
        streamDone <= False;
        await(pwStart);
        action
            $display($time," INFO: AFU Master FSM starting");
            $display($time,"      Size:          %016X",wed.entire.size.addr);
            $display($time,"      Start address: %016X",wed.entire.eaDst.addr);
            streamctrl.start(wed.entire.eaDst.addr,wed.entire.size.addr);
        endaction
        action
            await(streamctrl.done);
            $display($time," INFO: AFU Master FSM copy complete");
            streamDone <= True;
        endaction
        await(pwFinish);
        masterDone <= True;
        ret.enq(?);
    endseq;

    let ctlfsm <- mkFSMWithPred(ctlstmt,rstfsm.done);



    //// Command interface checking

    ClientU#(CacheCommand,CacheResponse) cmd <- mkClientUFromClient(cmdbuf.psl);

    FIFO#(MMIOResponse) mmResp <- mkFIFO1;

    interface SegmentedReg wedreg = wed;

    interface ClientU command = cmd;

    interface AFUBufferInterface buffer = cmdbuf.pslbuff;

    interface Server mmio;
        interface Get response = toGet(mmResp);

        interface Put request;
            method Action put (MMIORWRequest i);
                if (i matches tagged DWordWrite { index: .dwi, data: .dwd })
                begin
                    case (dwi) matches
                        4: pwStart.send;
                        5: pwFinish.send;
                        default: noAction;
                    endcase

                    mmResp.enq(WriteAck);
                end
                else if (i matches tagged DWordRead { index: .dwi })
                    case (dwi) matches
                        0:          mmResp.enq(tagged DWordData 64'h0123456700f00d00);
                        1:          mmResp.enq(tagged DWordData pack(wed.entire.eaDst.addr));
                        2:          mmResp.enq(tagged DWordData pack(wed.entire.size.addr));
                        3:          mmResp.enq(tagged DWordData (streamDone ? 64'h1111111111111111 : 64'h0));
                        4:          mmResp.enq(tagged DWordData (masterDone ? 64'hf00ff00ff00ff00f : 64'h1));
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

endmodule

import FIFOF::*;


(*clock_prefix="ha_pclock"*)
module mkSyn_AFUToHost(AFUHardware#(2));
    // stimulus generation
	Reg#(UInt#(32)) ctr <- mkReg(0);
	Reg#(UInt#(32)) stimctr <- mkReg(0);
	FIFOF#(Bit#(32)) stimFifo <- mkFIFOF;

	PipeOut#(Bit#(32)) iPipe =	f_FIFOF_to_PipeOut(stimFifo);

	Stmt stim = seq
        par
            stimFifo.clear;
            stimctr <= 0;
            ctr <= 0;
        endpar

		repeat(512) action
			stimFifo.enq(pack(stimctr));
			stimctr <= stimctr+1;
		endaction
	endseq;

    let stimfsm <- mkFSM(stim);

    rule alwaysStart;
        stimfsm.start;
    endrule

	function Action tapDisplay(Bit#(32) i) = action
		$display($time," Input %d: %08X",ctr,i);
		ctr <= ctr+1;
	endaction;

	PipeOut#(Bit#(32)) iPipeT <- mkTap(tapDisplay,iPipe);

    // AFU instantiation & wrapping
    let dut <- mkAFU_AFUToHostStream(iPipeT);
    let wrap <- mkDedicatedAFUNoParity(False,False,dut);

    AFUHardware#(2) hw <- mkCAPIHardwareWrapper(wrap);
    return hw;
endmodule

endpackage
