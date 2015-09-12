package Endian;

import StmtFSM::*;
import Vector::*;
import Reserved::*;
import AFU::*;
import DedicatedAFU::*;
import AFUHardware::*;

import Assert::*;

import FIFO::*;
import ClientServerU::*;
import MMIO::*;

import PSLTypes::*;

typedef struct {
    EAddress64          p;
    ReservedZero#(960)  resv;
} WED deriving(Bits,Eq);

typedef struct {
    Bit#(64) a64;
    Bit#(32) b32;
    Bit#(32) c32;
} Foo deriving (Bits);

import DReg::*;

module mkTieOffMMIO(Server#(MMIORWRequest,MMIOResponse));
    Reg#(Bool) sendResp <- mkDReg(False);

    interface Put request;
        method Action put(MMIORWRequest req);
            $display($time," WARNING: Tied-off MMIO port received request ",fshow(req));
            sendResp <= True;
        endmethod
    endinterface

    interface Get response;
        method ActionValue#(MMIOResponse) get if (sendResp);
            return tagged DWordData 64'h00000000deadbeef;
        endmethod
    endinterface
endmodule

typedef struct {
	UInt#(4)	expectA;
	UInt#(64)	expectNybbleUpcount;
	UInt#(956)	expectZero;
} Test2Struct deriving(Bits);

typedef struct {
    Vector#(16,Bit#(62)) a;
    UInt#(32)            pad;
} Test6Struct deriving(Bits);


module mkAFU_Endian(DedicatedAFUNoParity#(WED,2));
    //// WED reg
    SegReg#(WED,2,512) wed <- mkSegReg(unpack(?));


    //// Target reg for buffer writes
    SegReg#(Bit#(1024),2,512) bwData <- mkSegReg(unpack(?));


    Wire#(CacheResponse) wResp <- mkWire;
    Wire#(CacheCommand)  wCmd <- mkWire;


    FIFO#(void) ret <- mkFIFO1;


    Bit#(128) b = 128'h0001020304050608090a0b0c0d0e0f;

    //// Reset controller (also displays static packing information)

    Stmt rststmt = seq
        noAction;

        $display("Bluespec packing conventions");
        $display("============================");
        $display;
        
        $display("As bit vector: %32X",b);
        $display;
        
        action
            Vector#(2,Bit#(64)) p = unpack(b);
            $display("As two 64b vectors: p[1]=%32X",p[1]);
            $display("                    p[0]=%32X",p[0]);
            $display("Vectors are stored with highest index at MSB");
            $display;
        endaction

        action
            Foo t = unpack(b);
            $display("As struct: a64=%16X b32=%8X c32=%8X",t.a64,t.b32,t.c32);
            $display("Structs are stored with first element at MSB");
            $display;
        endaction

        action
            Tuple2#(Bit#(64),Bit#(64)) t = unpack(b);
            $display("As Tuple2#(Bit#(64),Bit#(64)): first=%16X, second=%16X",tpl_1(t),tpl_2(t));
            $display("Tuples are stored with the first element at MSB");
            $display;
        endaction

        $display($time," INFO: AFU Reset FSM completed");
    endseq;
    
    FSM rstfsm <- mkFSM(rststmt);

    Reg#(UInt#(8)) ctr <- mkReg(0);

    Stmt ctlstmt = seq
        while(ctr < 16)
        seq
            action
                let cmd = CacheCommand {
                    com:  Read_cl_s,
                    cabt: Abort,
                    csize: 128,
                    ctag: 0,
                    cch: 0,
                    cea: EAddress64 { addr: wed.entire.p.addr+(extend(ctr) << 7) }
                };
                wCmd <= cmd;
                $display($time," Test case %d",ctr);
                $display($time," ==========================");
                $display($time,fshow(cmd));
                $display;

                // NOTE: Should match stimulus sent in Endian.cpp
                $display("Expect ",
                case (ctr) matches
                    0: "uint8_t(ff) at lowest address, 0 elsewhere";
                    1: "uint64_t(0x0123456789abcdef) at lowest address";
                    2: "UInt#(4) 0xa, followed by UInt#(64) 0x0123456789abcdef placed in BDPIBitPacker";
                    3: "UInt#(8) 0x00..0x7f stored by BDPIAutoArrayPacker";
                    4: "UInt#(8) 0x00..0x7f stored as raw byte array in increasing memory order";
                    5: "UInt#(8) 0x00..0x7f stored as std::array<> iun BDPIAutoArrayPacker";
                    6: "Ascending Vector#(16,UInt#(62)) from BDPIAutoArrayBitPacker, values 0x300000000000000? ?=0..f";
                    default: "?";
                endcase);
            endaction

            action
                await(wResp.rtag == 0);
                $display($time," Response: ",fshow(wResp));

                $display($time,"    bwData[0]: %128X",bwData.seg[0]);
                $display($time,"    bwData[1]: %128X",bwData.seg[1]);
                
 
                case (ctr) matches
                	0: action
                		// Check that bwData.seg[0] MS byte is lowest-address byte
                		dynamicAssert(bwData.seg[0] == { 8'hff, 504'h0 }, "Test case 0: 0xff does not appear at MSB of bwData.seg[0]");
                		$display($time," Conclusion: bwad=0 -> half-line with lower memory address");
                		
                		// check that lowest address goes to MS byte in segreg
                		dynamicAssert(bwData.entire == { 8'hff, 1016'h0 }, "Test case 0: improper order in segreg.entire");
                		$display($time," Conclusion: segreg.entire provides the cacheline as a 1024b big-endian word (MS Byte at low address)");
                	endaction
                	
                	1: action
                		dynamicAssert(bwData.seg[0] == { 64'hefcdab8967452301, 448'h0 },"Test case 1: Unexpected byte order");
                		$display($time," Conclusion: bwdata stores lowest address byte in MSB; native endian ordering is preserved (uint64_t value byte-reversed)");
                	endaction
                	
                	2: action
                		// byte-reverse the entire cache line
                		Test2Struct st = unpack(endianSwap(bwData.entire));
                		
                		dynamicAssert(st.expectA == 4'ha,"Failed to unpack UInt#(4) of test struct");
                		dynamicAssert(st.expectNybbleUpcount == 64'h0123456789abcdef,"Failed to unpack UInt#(64) of test struct");
                		dynamicAssert(st.expectZero == 0,"Pad bytes are not zero as expected");
                		
                		$display($time," Conclusion: BDPIBitPacker writes in a little-endian format; once byte-reversed the cacheline is packed big-endian (BSV-compatible) and in forward element order");
                		$display($time,"               + Saves work on the host side (no need for endian flip on host)");
                		$display($time,"               + Preserves element ordering");
                		$display($time,"               - Need to byte reverse cacheline if packed with BDPIBitPacker, not if placed in standard struct");
                	endaction
                	
                	3: action                		
                		// Check: bwData[0] holds ascending bytes
                		//dynamicAssert(bwData.seg[0] == 512'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f,
                		//	"Unexpected byte order in bwData[0]");
                		
                		// Check: entire register unpacks to a descending byte count 
                		Vector#(128,UInt#(8)) desc = unpack(endianSwap(bwData.entire));
                		dynamicAssert(desc[0]    == 8'h7f,"Invalid byte ordering when unpacking ascending host byte array as descending BSV vector");
                		dynamicAssert(last(desc) == 8'h00,"Invalid byte ordering when unpacking ascending host byte array as descending BSV vector");
                		
                		$display($time," Conclusion: Bluespec stores vector v[N-1] in MSB, which is the lowest memory address");
                	endaction
                	
                	4: action
                	    // Checks: segreg half-line ordering, vector unpacking
                		
                		// Check: bwData[0] holds ascending bytes
                		dynamicAssert(bwData.seg[0] == 512'h000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f303132333435363738393a3b3c3d3e3f,
                			"Unexpected byte order in bwData[0]");
                		
                		// Check: entire register unpacks to a descending byte count 
                		Vector#(128,UInt#(8)) desc = unpack(bwData.entire);
                		dynamicAssert(desc[0]    == 8'h7f,"Invalid byte ordering when unpacking ascending host byte array as descending BSV vector");
                		dynamicAssert(last(desc) == 8'h00,"Invalid byte ordering when unpacking ascending host byte array as descending BSV vector");
                		
                		$display($time," Conclusion: Bluespec stores vector v[N-1] in MSB, which is the lowest memory address");
                	endaction
                	
                	5: action
                	    // Checks: segreg half-line ordering, vector unpacking, std::array bit packing
                		
                		// Check: entire register unpacks to an ascending byte count 
                		Vector#(128,UInt#(8)) asc = unpack(endianSwap(bwData.entire));
                		dynamicAssert(asc[0]    == 8'h00,"Invalid byte ordering when unpacking ascending host std::array<> as ascending BSV vector");
                		dynamicAssert(last(asc) == 8'h7f,"Invalid byte ordering when unpacking ascending host std::array<> as ascending BSV vector");
                		
                		$display($time," Conclusion: Bluespec stores vector v[N-1] in MSB, which is the lowest memory address");
                	endaction

                    6: action
                        Bit#(1024) b = endianSwap(bwData.entire);
                        Test6Struct st = unpack(b);

                        dynamicAssert(st.a[0]  == 62'h3000000000000000,"Unexpected value at LS element");
                        dynamicAssert(st.a[15] == 62'h300000000000000f,"Unexpected value at MS element");
                        dynamicAssert(st.pad == 0,"Pad bits are nonzero");
                    endaction
                	
                	default: $display;
                endcase
               

                ctr <= ctr+1;
                $display;
                $display;
            endaction


        endseq
        ret.enq(?);
    endseq;

    let ctlfsm <- mkFSMWithPred(ctlstmt,rstfsm.done);

    //// Command interface checking

    let mmioTieOff <- mkTieOffMMIO;

    interface SegmentedReg wedreg = wed;

    interface Server mmio = mmioTieOff;

    interface ClientU command;
        interface ReadOnly request;
            method CacheCommand _read = wCmd;
        endinterface

        interface Put response = toPut(asIfc(wResp));
    endinterface


    interface AFUBufferInterface buffer;
        interface Put readdata;
            method Action put(BufferWrite bw) = bwData.seg[bw.bwad]._write(bw.bwdata);
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

(*clock_prefix="ha_pclock"*)
module mkSyn_Endian(AFUHardware#(2));
    let dut <- mkAFU_Endian;
    let wrap <- mkDedicatedAFUNoParity(False,False,dut);

    AFUHardware#(2) hw <- mkCAPIHardwareWrapper(wrap);
    return hw;
endmodule

endpackage
