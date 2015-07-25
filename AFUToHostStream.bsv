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

    // PSL interface
    interface Client#(CacheCommand,CacheResponse)       cmd;
    interface ServerARU#(BufferReadRequest,Bit#(512))   br;

    // the outgoing stream
    interface Put#(Bit#(1024)) ostream;
endinterface


function Bit#(n) padpack(data_t i) provisos (Bits#(data_t,ni),Add#(ni,__some,n)) = extend(pack(i));


/** Sinks a stream to host memory.
 *
 * The user starts the transfer by providing an address and a size, then is able to push (size) bytes to the host in 1024b chunks.
 *
 * Currently requires cache-aligned ea and size. 
 */

module mkAFUToHostStream(AFUToHostStream)
    provisos (
        NumAlias#(nt,4));

    Integer stepBytes=128;
    Integer alignBytes=stepBytes;

    // Manage the request tags
    let mgr <- mkTagManager(Vector#(nt,RequestTag)'(genWith(fromInteger)),False);

    // keep track of completion status
    Vector#(nt,Reg#(Bool)) completed <- replicateM(mkReg(True));

    Reg#(UInt#(64)) eaStart   <- mkReg(0);
    Reg#(UInt#(64)) ea        <- mkReg(0);
    Reg#(UInt#(64)) eaEnd     <- mkReg(0);

    FIFO#(CacheCommand) oCmd <- mkFIFO;

    WriteBuf#(2) wbuf <- mkAFUWriteBuf(4);

    PulseWire pwStart <- mkPulseWire;

    method Action start(UInt#(64) ea0,UInt#(64) size);
        eaStart <= ea0;
        ea <= ea0;
        eaEnd <= ea0+size;

        pwStart.send;

        dynamicAssert(ea0 % fromInteger(alignBytes) == 0,    "Effective address is not properly aligned");
        dynamicAssert(size % fromInteger(alignBytes) == 0,   "Transfer size is not properly aligned");
    endmethod

    method Bool done = ea==eaEnd && foldl1( \&& , read(completed));

    interface Client cmd;
        interface Get request = toGet(oCmd);

        interface Put response;
            method Action put(CacheResponse r);
                case (r.response) matches
                    Done:
                        action
                            $display($time," Write completion for tag %X",r.rtag);
                            completed[r.rtag] <= True;

                            mgr.free(r.rtag);

                            // TODO: Change this so we can restart cleanly?
//                            dynamicAssert(!completed[r.rtag],"Completion received for unused tag");
                        endaction
					Paged:
					action
						completed[r.rtag] <= True;
						mgr.free(r.rtag);
						$display($time," WARNING: PAGED response ignored for tag %X",r.rtag);
					endaction
                        
                    default:
                        action
                            $display($time,"ERROR: Invalid command code received ",fshow(r));
                            dynamicAssert(False,"Invalid command code received");
                        endaction
                endcase
                    // Aerror
                    // Derror
                    // Nlock
                    // Nres
                    // Flushed
                    // Fault
                    // Failed
                    // Credit
                    // Paged
                    // Invalid
            endmethod

        endinterface
    endinterface

    interface ServerARU br;
        interface Put request  = wbuf.pslin.request;
        interface Get response = wbuf.pslin.response;
    endinterface

    interface Put ostream;
        method Action put(Bit#(1024) i) if (ea != eaEnd && !pwStart);
            // get tag and write data to buffer
            let t <- mgr.acquire;
            completed[t] <= False;
            wbuf.write(t,i);

            // enq command
            let cmd = CacheCommand { com: Write_mi, ctag: t, cabt: Abort, cea: EAddress64 { addr: ea }, cch: 0, csize: fromInteger(stepBytes) };
            oCmd.enq(cmd);
            ea <= ea + fromInteger(stepBytes);
        endmethod
    endinterface
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




	//// Stream consumer: fix endianness, unfunnel, reverse elements, and pack into 1024b vector
	PipeOut#(Vector#(1,Bit#(32))) iEndian <- mkFn_to_Pipe(compose(unpack,compose(pack,endianSwap)),pi);
    PipeOut#(Vector#(32,Bit#(32))) iUnFun <- mkUnfunnel(False,iEndian);

    PipeOut#(Bit#(1024)) stream <- mkFn_to_Pipe(compose(pack,reverse),iUnFun);



    //// Host -> AFU stream controller

    let streamctrl <- mkAFUToHostStream;

	mkSink_to_fa(streamctrl.ostream.put,stream);

    FIFO#(void) ret <- mkFIFO1;

    Stmt ctlstmt = seq
        action
            $display($time," INFO: AFU Master FSM starting");
            $display($time,"      Size:          %016X",wed.entire.size.addr);
            $display($time,"      Start address: %016X",wed.entire.eaDst.addr);
            streamctrl.start(wed.entire.eaDst.addr,wed.entire.size.addr);
        endaction
        await(streamctrl.done);
        $display($time," INFO: AFU Master FSM copy complete");
        ret.enq(?);
    endseq;

    let ctlfsm <- mkFSMWithPred(ctlstmt,rstfsm.done);



    //// Command interface checking

    ClientU#(CacheCommand,CacheResponse) cmd <- mkClientUFromClient(streamctrl.cmd);

	Wire#(Bit#(512)) respW <- mkWire;
	
	rule getBufferResponse;
		respW <= streamctrl.br.response;
	endrule


    interface SegmentedReg wedreg = wed;

    interface ClientU command = cmd;

    interface AFUBufferInterface buffer;
//        interface Put readdata = streamctrl.bw;
        interface ServerAFL writedata;
			interface Put request;
				method Action put(BufferReadRequest req) = streamctrl.br.request.put(req);
			endinterface
			interface ReadOnly response;
				method Bit#(512) _read = respW;
			endinterface
		endinterface
    endinterface

// no MMIO support
    interface Server mmio;
        interface Get response;
            method ActionValue#(MMIOResponse) get if (False) = actionvalue return ?; endactionvalue;
        endinterface

        interface Put request;
            method Action put (MMIORWRequest i) = noAction;
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

    method AFUAttributes attributes = AFUAttributes {
        brlat: 2,
        pargen: False,
        parcheck: False };

endmodule

import FIFOF::*;


(* clock_prefix="ha_pclock", no_default_reset *)

module mkSyn_AFUToHost(AFUHardware#(2));
    //// Reset generation

    let por <- mkPOR(1,reset_by noReset);
    let clk <- exposeCurrentClock;
    MakeResetIfc rstctrl <- mkResetSync(0,False,clk,reset_by noReset);

	//// RNG for write data
//	let rng <- mkBDPIIStream(bsv_makeMersenneTwister19937,reset_by rstctrl.new_rst);
//	PipeOut#(Bit#(32)) iPipe <- mkSource_from_fav(rng.next.get,reset_by rstctrl.new_rst);

	Reg#(UInt#(32)) ctr <- mkReg(0,reset_by rstctrl.new_rst);
	Reg#(UInt#(32)) stimctr <- mkReg(0,reset_by rstctrl.new_rst);
	FIFOF#(Bit#(32)) stimFifo <- mkFIFOF(reset_by rstctrl.new_rst);

	PipeOut#(Bit#(32)) iPipe =	f_FIFOF_to_PipeOut(stimFifo);

	Stmt stim = seq
		repeat(512) action
			stimFifo.enq(pack(stimctr));
			stimctr <= stimctr+1;
		endaction

		repeat(10000) noAction;

	endseq;

	mkAutoFSM(stim,reset_by rstctrl.new_rst);



	function Action tapDisplay(Bit#(32) i) = action
		$display($time," Input %d: %08X",ctr,i);
		ctr <= ctr+1;
	endaction;

	PipeOut#(Bit#(32)) iPipeT <- mkTap(tapDisplay,iPipe);


    let dut <- mkAFU_AFUToHostStream(iPipeT,reset_by rstctrl.new_rst);
    let wrap <- mkDedicatedAFUNoParity(False,False,dut,reset_by rstctrl.new_rst);

    rule doPOR if (por.isAsserted);
        rstctrl.assertReset;
    endrule

    AFUHardware#(2) hw <- mkCAPIHardwareWrapper(wrap,reset_by rstctrl.new_rst);
    return hw;
endmodule

endpackage
