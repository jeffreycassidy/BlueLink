package Memcopy2;

import StmtFSM::*;
import Vector::*;
import Reserved::*;
import DedicatedAFU::*;
import AFUHardware::*;

import AFUToHostStream::*;
import HostToAFUStream::*;
import AFU::*;

import FIFO::*;
import ClientServerU::*;
import CmdBuf::*;
import MMIO::*;

import Common::*;

import PSLTypes::*;

import Endianness::*;

/** Interface uses HostNative byte ordering. C/C++ structs appear in correct element order but need endian swap for each element.
 */

typedef struct {
    LittleEndian#(EAddress64) eaSrc;
    LittleEndian#(EAddress64) eaDst;
    LittleEndian#(EAddress64) size;

    ReservedZero#(64)   padA;

    ReservedZero#(256)  padB;

    ReservedZero#(512)  padC;
} MemcopyWED deriving(Bits,Eq);

module mkAFU_Memcopy2(DedicatedAFUNoParity#(2));
    //// WED reg
    SegReg#(MemcopyWED,2,512) wedreg <- mkSegReg(HostNative,unpack(?));
    MemcopyWED wed = wedreg.entire;

    //// Reset controller
    Stmt rststmt = seq
        noAction;
        $display($time," INFO: AFU Reset FSM completed");
    endseq;
    
    FSM rstfsm <- mkFSM(rststmt);


    CacheCmdBuf#(2,2) cmdbuf <- mkCmdBuf(16);


    let pwStart <- mkPulseWire;
    let pwFinish <- mkPulseWire;

    // Host->AFU stream controller & output data
    let { istreamctrl, stream } <- mkHostToAFUStream(8,cmdbuf.client[1],EndianSwap);

    // AFU->Host controller
    let ostreamctrl <- mkAFUToHostStream(8, cmdbuf.client[0], EndianSwap, stream);

    FIFO#(void) ret <- mkFIFO1;

    Reg#(Bool) copyDone <- mkReg(False);
    Reg#(Bool) masterDone <- mkReg(False);

    EAddress64 eaSrc = unpackle(wed.eaSrc);
    EAddress64 eaDst = unpackle(wed.eaDst);
    EAddress64 size  = unpackle(wed.size);

    Stmt ctlstmt = seq
        masterDone <= False;
        copyDone <= False;
        await(pwStart);
        action
            $display($time," INFO: AFU Master FSM starting");
            $display($time,"      Size:          %016X",size );
            $display($time,"      Src address: %016X",  eaSrc);
            $display($time,"      Dst address: %016X",  eaDst);

            istreamctrl.start(eaSrc.addr,size.addr);
            ostreamctrl.start(eaDst.addr,size.addr);
        endaction

        action
            await(ostreamctrl.done);
            $display($time," INFO: AFU Master FSM copy complete");
            copyDone <= True;
        endaction
        await(pwFinish);
        masterDone <= True;
        ret.enq(?);
    endseq;

    let ctlfsm <- mkFSMWithPred(ctlstmt,rstfsm.done);



    //// Command interface checking

    ClientU#(CacheCommand,CacheResponse) cmd <- mkClientUFromClient(cmdbuf.psl);


    FIFO#(MMIOResponse) mmResp <- mkFIFO1;

    interface ClientU command = cmd;

    interface AFUBufferInterface buffer = cmdbuf.pslbuff;

    interface Vector wedwrite = map(regToWriteOnly,wedreg.seg);

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
                        1:          mmResp.enq(tagged DWordData pack(eaDst.addr));
                        2:          mmResp.enq(tagged DWordData pack(size.addr));
                        3:          mmResp.enq(tagged DWordData (copyDone   ? 64'h1111111111111111 : 64'h0));
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

(*clock_prefix="ha_pclock"*)
module mkSyn_Memcopy2(AFUHardware#(2));

    let dut <- mkAFU_Memcopy2;
    let wrap <- mkDedicatedAFUNoParity(False,False,dut);

    AFUHardware#(2) hw <- mkCAPIHardwareWrapper(wrap);
    return hw;
endmodule

endpackage
