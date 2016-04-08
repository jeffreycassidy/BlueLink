package Memcopy2;

import StmtFSM::*;
import Vector::*;
import Reserved::*;
import DedicatedAFU::*;
import AFUHardware::*;
import AFUShims::*;

import ResourceManager::*;
import DReg::*;
import ConfigReg::*;

import AFU::*;

import FIFOF::*;
import ClientServerU::*;
import MMIO::*;

import ProgrammableLUT::*;

import PAClib::*;

import PSLTypes::*;

import Endianness::*;
import HList::*;

function EAddress64 offset(EAddress64 addr,UInt#(n) o) provisos (Add#(n,__some,64));
    return EAddress64 { addr: addr.addr + extend(o) };
endfunction

typedef struct {
    LittleEndian#(EAddress64) addrFrom;
    LittleEndian#(EAddress64) addrTo;
    LittleEndian#(UInt#(64))  size;

    Reserved#(832)  resv;
} WED deriving(Bits);

typedef enum { Resetting, Ready, Running, Done } Status deriving (Eq,FShow,Bits);

typedef 64 NTags;

module mkAFU_Memcopy2(DedicatedAFU#(2));
    //// WED reg
    Vector#(2,Reg#(Bit#(512))) wedSegs <- replicateM(mkReg(0));
    WED wed = concatSegReg(wedSegs,LE);

    Reg#(EAddress64) addrFrom <- mkReg(0);
    Reg#(EAddress64) addrTo <- mkReg(0);
    Reg#(UInt#(NTags))  sizeRemain <- mkReg(0);

    // Internal status
    let pwStart <- mkPulseWireOR;
    let pwTerm  <- mkPulseWire;
    Reg#(Status) st <- mkReg(Resetting);


    ////// Command management
    
    // Manage (nTags) tags with bypass enabled
    let tagMgr <- mkResourceManager(valueOf(NTags),False,False);

    // true indicates read has been completed & write has not
    //      NOTE: ConfigReg used to break a dependency cycle
    //          the new value doesn't need to propagate within a single cycle since PSL has nonzero latency to turn a command around
    Vector#(NTags,Reg#(Bool)) tagReadComplete <- replicateM(mkConfigReg(False));

    // Storage
    Lookup#(8,EAddress64) addrLUT   <- mkZeroLatencyLookup(hCons(AlteraStratixV,hNil),valueOf(NTags));
    Lookup#(8,Bit#(512))  txbuf     <- mkZeroLatencyLookup(hCons(AlteraStratixV,hNil),valueOf(NTags)*2);

    // Command/response buffers
    Wire#(CacheResponse)    iRespW <- mkWire;
    FIFOF#(CacheResponse)   iResp <- mkLFIFOF;
    FIFOF#(CacheCommand)    oCmd  <- mkLFIFOF;

    // Buffer data
    Reg#(Maybe#(BufferWrite))       bwIn        <- mkDReg(tagged Invalid);
    Reg#(Maybe#(BufferReadRequest)) brIn        <- mkDReg(tagged Invalid);
    Reg#(Maybe#(Bit#(512)))         brResponse  <- mkDReg(tagged Invalid);


    // done means all read requests are done and no tags remain locked
    Bool done = !(List:: \or )(tagMgr.status);

    // Return value
    Wire#(AFUReturn) ret <- mkWire;

    Stmt masterstmt = seq
        // (reset logic)
        st <= Resetting;

        // reset finished
        st <= Ready;

        // wait for start pulse
        await(pwStart);
        action
            $display($time," INFO: AFU Master FSM starting");
            $display($time,"      Src address: %016X",unpackle(wed.addrFrom).addr);
            $display($time,"      Dst address: %016X",unpackle(wed.addrTo).addr);
            $display($time,"      Size:        %016X",unpackle(wed.size));

            sizeRemain <= unpackle(wed.size);
            addrFrom <= unpackle(wed.addrFrom);
            addrTo <= unpackle(wed.addrTo);
            st <= Running;
        endaction

        // wait until last read is issued
        action
            await(sizeRemain == 0);
            $display($time," INFO: Last read has been issued");
        endaction

        // allow last request to percolate through ResourceManager
        repeat(2) noAction;

        // wait until last write completes
        while(((List:: \or )(tagMgr.status)) || !Vector:: \and (readVReg(tagReadComplete)))
        action
            $write("Tag status (L=locked):   ");
            for(Integer i=0;i<64;i=i+1)
                $write(tagMgr.status[i] ? "L" : ".");
            $display;
            $write("Tag read unfinished (U): ");
            for(Integer i=0;i<64;i=i+1)
                $write(tagReadComplete[i] ? "." : "U");
            $display;
        endaction

        action
            await(done);
            $display($time," INFO: Last command has been completed");
        endaction

        action
            $display($time, " INFO: Memcopy2 finished and awaiting termination pulse on MMIO");
            st <= Done;
        endaction

        await(pwTerm);
        ret <= Done;
    endseq;

    let masterfsm <- mkFSM(masterstmt);

    rule respond;
        iResp.enq(iRespW);
    endrule

    // arbitrate between command issuers
    (* descending_urgency="writeWhenReadCompletes,readWhileNotFinished,freeTagWhenCompletes,droppedResponse" *)


    rule writeWhenReadCompletes if (iResp.first.response == Done && !tagReadComplete[iResp.first.rtag]);
        iResp.deq;
        let tag = iResp.first.rtag;

        // find the write address
        let addr <- addrLUT.lookup(tag);

        // send write command, mark read as completed
        oCmd.enq(CacheCommand { ctag: tag, com: Write_mi, cabt: Strict, cea: addr, cch: 0, csize: 128 });
        tagReadComplete[tag] <= True;

        $display($time," INFO: Read  completed for tag %02X, issuing write ",iResp.first.rtag);
    endrule

    rule freeTagWhenCompletes if (iResp.first.response != Done || tagReadComplete[iResp.first.rtag]);
        iResp.deq;

        if (iResp.first.response == Done)
            $display($time," INFO: Write completed for tag %02X",iResp.first.rtag);
        else
            $display($time," ERROR: Received fault response ",fshow(iResp.first));

        // need to be careful here: if bypass == True then unlock before lock
        // but if False, require lock before unlock which yields a cycle with rule readWhileNotFinished
        //
        //      tagReadComplete reg -> read before write
        //      unlock
        //
        // solved by making tagReadComplete a ConfigReg since it's never meaningfully updated and read in the same clock

        tagMgr.unlock(iResp.first.rtag);
    endrule

    rule readWhileNotFinished if (sizeRemain != 0);
        // get tag if available (implicit condition)
        let tag <- tagMgr.nextAvailable.get;

        $display($time," INFO: Issuing read with tag %02X",tag);

        // issue command
        oCmd.enq(CacheCommand { ctag: tag, com: Read_cl_na, cabt: Strict, cea: addrFrom, cch: 0, csize: 128 });

        // store write address for later use, mark as read incomplete
        addrLUT.write(tag,addrTo);
        tagReadComplete[tag] <= False;

        // bump pointers
        addrFrom    <= addrFrom+128;
        addrTo      <= addrTo+128;
        sizeRemain  <= sizeRemain-128;
    endrule

    rule droppedResponse;
        iResp.deq;
        $display($time," ERROR: Dropped response ",fshow(iResp.first));
    endrule

    (* fire_when_enabled *)
    rule doBufferWrite if (bwIn matches tagged Valid .bw);
        txbuf.write((extend(bw.bwtag)<<1)|extend(bw.bwad),bw.bwdata);
    endrule

    (* fire_when_enabled *)
    rule replyToBufferRequest if (brIn matches tagged Valid .br);
        let brData <- txbuf.lookup((extend(br.brtag)<<1) | extend(br.brad));
        brResponse <= tagged Valid brData;
    endrule



    //// Command interface checking

    FIFOF#(MMIOResponse) mmResp <- mkGFIFOF1(True,False);


    mkSink(f_FIFOF_to_PipeOut(oCmd));

    interface ClientU command;
        interface ReadOnly request;
            method CacheCommand _read = oCmd.first;
        endinterface
        interface Put response = toPut(asIfc(iRespW));
    endinterface

    interface AFUBufferInterface buffer;
        interface ServerAFL writedata;
            interface Put request;
                method Action put(BufferReadRequest br);
                    brIn <= tagged Valid br;
                endmethod
            endinterface
            interface ReadOnly response;
                method Bit#(512) _read if (brResponse matches tagged Valid .r) = r;
            endinterface
        endinterface

        interface Put readdata;
            method Action put(BufferWrite bw);
                bwIn <= tagged Valid bw;
            endmethod
        endinterface
    endinterface

    interface Server mmio;
        interface Get response = toGet(mmResp);

        interface Put request;
            method Action put (MMIORWRequest mm);
                case (mm) matches
                    tagged DWordWrite { index: 0, data: 0 }:
                        action
                            pwStart.send;
                            mmResp.enq(64'h0);
                        endaction
                    tagged DWordWrite { index: 0, data: 1 }:
                        action
                            pwTerm.send;
                            mmResp.enq(64'h0);
                        endaction
                    tagged DWordRead { index: .i }:
                        mmResp.enq(case(i) matches
                            0:  case (st) matches
                                    Resetting: 0;
                                    Ready: 2;       // ready here has same meaning as 'waiting' in original Memcopy
                                    Running: 3;
                                    Done: 4;
                                endcase
                            1:  pack(unpackle(wed.size));
                            2:  pack(unpackle(wed.addrFrom).addr);
                            3:  pack(unpackle(wed.addrTo).addr);
                            default: 64'hdeadbeefbaadc0de;
                        endcase);
                    default:
                        mmResp.enq(64'h0);
                endcase
            endmethod
        endinterface

    endinterface

    method Action wedwrite(UInt#(6) i,Bit#(512) val) = asReg(wedSegs[i])._write(val);

    method Action   rst = masterfsm.start;
    method Bool     rdy = (st == Ready);

    method Action start(EAddress64 ea,UInt#(8) croom) = pwStart.send;
    method ActionValue#(AFUReturn) retval = actionvalue return ret; endactionvalue;

endmodule

(*clock_prefix="ha_pclock"*)
module mkMemcopy2AFU(AFUHardware#(2));

    let dut <- mkAFU_Memcopy2;
    let afu <- mkDedicatedAFU(dut);

    AFUHardware#(2) hw <- mkCAPIHardwareWrapper(afuParityWrapper(afu));
    return hw;
endmodule

endpackage
