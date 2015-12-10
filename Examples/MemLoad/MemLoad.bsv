package MemLoad;

import DedicatedAFU::*;
import AFUHardware::*;
import PSLTypes::*;
import AFU::*;
import ClientServerU::*;
import MMIO::*;
import MMIOConfig::*;

import MemScanChain::*;
import AlteraM20k::*;

import PAClib::*;
import PAClibx::*;

import FIFOF::*;
import StmtFSM::*;
import Reserved::*;

import Assert::*;

import Endianness::*;

import DReg::*;

import Vector::*;

import CmdBuf::*;
import CmdCounter::*;
import HostToAFUBulk::*;
import AFUToHostStream512::*;

import HList::*;
import BLProgrammableLUT::*;

import CAPIStream::*;

HCons#(MemSynthesisStrategy,HNil) syn = hCons(AlteraStratixV,hNil);

// WED structure
typedef struct {
    LittleEndian#(EAddress64)   pSrc;
    LittleEndian#(EAddress64)   pDst;

    LittleEndian#(UInt#(24))    size;
    ReservedZero#(40)           padSize;

    ReservedZero#(64)           pad0;

    ReservedZero#(256)          pad1;

    ReservedZero#(512)          pad2;
} WED deriving (Bits);


module [Module] mkMemLoad(DedicatedAFU#(2))
    provisos (
        NumAlias#(depth,65536),                 // config params
        NumAlias#(nBanks,16),
        Log#(nBanks,nbBank),

        Mul#(bankDepth,nBanks,depth),           // derived params
        Log#(bankDepth,nbOffset)
        );
    Integer depth=valueOf(depth);               // convenience: provide Integer as well as numeric type
    Integer nBanks = valueOf(nBanks);
	Integer bankDepth = valueOf(bankDepth);

    // WED register & return for DedicatedAFU
    SegReg#(WED,2,512) wed <- mkSegReg(HostNative,unpack(1024'h0));

    // Timestamp for transactions (zeroes out at reset)
    Reg#(UInt#(64)) timestamp <- mkReg(0);
    rule incrTimestamp;
        timestamp <= timestamp+1;
    endrule

    Reg#(UInt#(48)) tsRstDone <- mkReg(0);
    Reg#(UInt#(48)) tsH2AStart<- mkReg(0);
    Reg#(UInt#(48)) tsH2ADone <- mkReg(0);
    Reg#(UInt#(48)) tsA2HStart<- mkReg(0);
    Reg#(UInt#(48)) tsA2HDone <- mkReg(0);


    // Internal status registers
    Reg#(Bool) rstDone <- mkReg(False);


    // incoming status controls (True,False) -> unguarded enq (gives warning), guarded deq
    FIFOF#(void) startReq   <- mkGFIFOF1(True,False);
    FIFOF#(void) termReq    <- mkGFIFOF1(True,False);
    FIFOF#(void) finishReq  <- mkGFIFOF1(True,False);


    // status return
    FIFOF#(AFUReturn) ret <- mkFIFOF1;



    ////// Command-response pathway
    CacheCmdBuf#(2,2) cmdbuf    <- mkCmdBuf(32);                        // use 32 tags
    CmdCounter#(32) cmdCounter  <- mkCmdCounter(cmdbuf.psl);            // 32b command counters
    let cmdbufu                 <- mkClientUFromClient(cmdCounter.c);



	////// BRAM with scan chain

	FIFOF#(MemItem#(UInt#(24),Bit#(512))) scanChainIn  <- mkFIFOF;

	// The BRAMs (dual-port with stall capability)
	Vector#(16,BRAM_DUAL_PORT_Stall#(UInt#(nbOffset),Bit#(512))) br <- replicateM(mkBRAM2Stall(bankDepth));

	// extract port A from all BRAMs and put the implicit condition wrapper on it
	function BRAM_PORT_Stall#(idxT,dataT) getPortA(BRAM_DUAL_PORT_Stall#(idxT,dataT) _br) = _br.a;

	Vector#(16,BRAM_PORT_SplitRW#(UInt#(nbOffset),Bit#(512))) brs <- mapM(mkBRAMPortSplitRW, map(getPortA,br));


	PipeOut#(Bit#(512)) scanChainOut <- mkMemScanChain(brs,f_FIFOF_to_PipeOut(scanChainIn));


    // MMIO-based readback scheme
    FIFOF#(UInt#(64)) mmMemRead <- mkGFIFOF1(True,False);                       // address
        UInt#(4)        readbackBank  = truncate(mmMemRead.first >> 16);         // 16 banks -> 4 bank bits
        UInt#(nbOffset) readbackOffs  = truncate(mmMemRead.first >> 3);          // 512B halfline index addressing
        UInt#(3)        readbackShift = truncate(mmMemRead.first);               // shift within the halfline

    Reg#(Maybe#(Tuple2#(UInt#(nbBank),UInt#(nbOffset)))) brReadAddrBank <- mkDReg(tagged Invalid);

    Vector#(16,Reg#(Maybe#(UInt#(nbOffset)))) brReadAddrB <- replicateM(mkDReg(tagged Invalid));
    Vector#(16,Reg#(Bool)) brDeqB <- replicateM(mkDReg(False));

    Reg#(Bit#(64)) mmReadbackReg <- mkReg(64'h0);



    ////// Host -> AFU stream
    HostToAFUBulkIfc#(UInt#(24),UInt#(64),Bit#(512)) host2afu <- mkHostToAFUBulk(32,cmdbuf.client[0],EndianSwap);



    ////// AFU -> Host stream
	Reg#(UInt#(24)) ctr <- mkReg(0);
	Reg#(Bool) readbackEn <- mkReg(False);
	AFUToHostStreamIfc#(UInt#(64),Bit#(512)) afu2host <- mkAFUToHostStream512(syn,32,32,cmdbuf.client[1],EndianSwap);



    // Forward the reads to the block RAMs
    rule doPortBRead if (brReadAddrBank matches tagged Valid { .bank, .offs });
        brReadAddrB[bank] <= tagged Valid offs;
    endrule

    for(Integer i=0;i<nBanks;i=i+1)
    begin
        rule doBankPortBRead if (brReadAddrB[i] matches tagged Valid .addr);
            br[i].b.put(False,addr,?);
            brDeqB[i] <= True;
        endrule

        rule doPortBDeq if (brDeqB[i]);
            br[i].b.deq;
        endrule
    end



    Stmt mainstmt = seq
        ////// Reset actions
        action
            $display($time," INFO: AFU reset complete");
            rstDone <= True;
            tsRstDone <= truncate(timestamp);

            tsH2AStart <= 0;
            tsH2ADone <= 0;
            tsA2HStart <= 0;
            tsA2HDone <= 0;
        endaction


        ////// Main FSM

        // Start Host->AFU transfer
        action
			$display($time," INFO: Starting host->AFU transfer from address %X size %d",wed.entire.pSrc._payload.addr,wed.entire.size._payload);
            startReq.deq;
            host2afu.ctrl.start(
                wed.entire.pSrc._payload.addr,
                extend(wed.entire.size._payload));
            tsH2AStart <= truncate(timestamp);
        endaction

		while(!host2afu.ctrl.done)
			action
				let { idx, data } <- host2afu.data.get;
                $display($time," INFO: ScanChainIn received write to %X: %X",idx,data);
				scanChainIn.enq(tagged Request tuple2(idx,tagged Write data));
			endaction

        // Wait for completion
		action
			$display($time," INFO: Host->AFU transfer done");
	        tsH2ADone <= truncate(timestamp);
		endaction



        // Serve MMIO requests
        // mmMemRead is static throughout each iteration of the loop, so use multicycle paths
        //      mmMemRead -> mmReadbackReg 9 cycles
        //      BRAM q_b -> mmReadbackReq 5 cycles

        while (!finishReq.notEmpty)
            seq
                action
                    await(mmMemRead.notEmpty);
                    brReadAddrBank <= tagged Valid tuple2(readbackBank, readbackOffs);
                endaction

                noAction;                   // 1 tick  for brReadAddrBank -> brReadAddrB[XX]
                repeat(2) noAction;         // 2 ticks for brReadAddrB[XX] -> br[XX].b.put -> br[XX].b.read (ireg + oreg)

                repeat(4) noAction;         // multicycle (5) return & mux path
                action
                    Vector#(8,Bit#(64)) tmp = unpack(br[readbackBank].b.read);
                    $display($time," INFO: Readback value %X",tmp[readbackShift]);
                    mmReadbackReg <= tmp[readbackShift];
                    mmMemRead.deq;
                endaction
            endseq

        finishReq.deq;




        // Start AFU -> Host transfer
        action
			$display($time," INFO: Starting AFU->host transfer to address %X size %d",wed.entire.pDst._payload.addr,wed.entire.size._payload);
            tsA2HStart <= truncate(timestamp);
            afu2host.ctrl.start(
                wed.entire.pDst._payload.addr,
                extend(wed.entire.size._payload));
			ctr <= 0;

			readbackEn <= True;
        endaction

		// Issue requests
		while (ctr < truncate(wed.entire.size._payload >> log2(transferBytes)))
			action
				scanChainIn.enq(tagged Request tuple2(ctr,Read));
				ctr <= ctr + 1;
                $display($time," INFO: ScanChainIn requesting read from index %X",ctr);
			endaction

        // Wait for completion
        action
			$display($time," INFO: AFU->host transfer done");
            tsA2HDone <= truncate(timestamp);
            await(afu2host.ctrl.done);
			readbackEn <= False;
        endaction

        action
            $display($time," INFO: Main FSM finished and awaiting termination");
        endaction



        ////// Await termination

        action
            termReq.deq;
            $display($time," INFO: Termination pulse received");
        endaction

        ret.enq(Done);
    endseq;

    let mainfsm <- mkFSM(mainstmt);

	let mainstarter <- mkOnce(mainfsm.start);
	rule initStartMain;
		mainstarter.start;
	endrule



    function Action showScanChainOutput(Bit#(512) d) = $display($time," INFO: ScanChainOut data %X",d);
    let scanChainOutT <- mkTap(showScanChainOutput,scanChainOut);


	mkSink_to_fa(afu2host.data.put, gatePipeOut(readbackEn, scanChainOutT));


    FIFOF#(MMIORWRequest) mmReq <- mkGFIFOF1(True,False);
    FIFOF#(MMIOResponse) mmResp <- mkGFIFOF1(True,False);

    rule handleMMIO;
        let cmd = mmReq.first;
        mmReq.deq;

        if (cmd matches tagged DWordWrite { index: .idx, data: .data })
        begin
            case (idx) matches
                0:  mmMemRead.enq(unpack(data));
                1:  finishReq.enq(?);
                2:  termReq.enq(?);
                default: dynamicAssert(False,"MMIO DWordWrite to invalid index");
            endcase
            mmResp.enq(WriteAck);
        end
        else if (cmd matches tagged DWordRead { index: .idx })
            case (idx) matches
                0:  mmResp.enq(tagged DWordData pack(mmReadbackReg));

                2:  mmResp.enq(tagged DWordData extend(pack(tsH2AStart)));
                3:  mmResp.enq(tagged DWordData extend(pack(tsH2ADone)));

                4:  mmResp.enq(tagged DWordData extend(pack(tsA2HStart)));
                5:  mmResp.enq(tagged DWordData extend(pack(tsA2HDone)));

                default:
                action
                    mmResp.enq(tagged DWordData 64'h0);
                    dynamicAssert(False,"MMIO DWordRead to invalid index");
                endaction
            endcase
        else
        begin
            dynamicAssert(False,"MMIO word operations not supported");
            mmResp.enq(WriteAck);
        end
    endrule

	function WriteOnly#(t) regToWriteOnly(Reg#(t) regifc) = interface WriteOnly;
		method Action _write(t i) = regifc._write(i);
	endinterface;


    interface Vector wedwrite = map(regToWriteOnly,wed.seg);

    interface ClientU command = cmdbufu;

    interface AFUBufferInterface buffer = cmdbuf.pslbuff;

    interface Server mmio;
        interface Put request  = toPut(mmReq );
        interface Get response = toGet(mmResp);
    endinterface

    method Action start = startReq.enq(?);

    method ActionValue#(AFUReturn) retval;
        ret.deq;
        return ret.first;
    endmethod

	method Bool rst = rstDone;
endmodule

(* clock_prefix="ha_pclock" *)

module [Module] mkSyn_MemLoad(AFUHardware#(2));
	let dut <- mkMemLoad;
    let _wrap <- mkDedicatedAFU(dut);
    AFUHardware#(2) hw <- mkCAPIHardwareWrapper(_wrap);
    return hw;
endmodule

endpackage
