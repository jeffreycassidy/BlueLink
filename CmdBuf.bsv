package CmdBuf;

import PSLTypes::*;
import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;
import BLProgrammableLUT::*;

import DReg::*;

import PAClibx::*;

import HList::*;

import AFU::*;
import ClientServerU::*;

import ResourceManager::*;

import Assert::*;

typedef union tagged {
    void        Any;
    RequestTag  SpecificTag;
} TagSpecifier deriving(Eq,Bits);

typedef struct {
    PSLCommand              com;
    PSLTranslationOrdering  cabt;
    EAddress64              cea;
    UInt#(12)               csize;
} CmdWithoutTag deriving(Bits);

instance FShow#(CmdWithoutTag);
    function Fmt fshow(CmdWithoutTag c) = fshow("CmdWithoutTag ") + fshow(c.com) +
        fshow(" cabt=") + fshow(c.cabt) + fshow(" addr=") + fshow(c.cea) + fshow(" csize=") + fshow(c.csize);
endinstance

function CacheCommand bindCommandToTag(RequestTag ctag, CmdWithoutTag cmd) = CacheCommand {
    com: cmd.com,
    cabt: cmd.cabt,
    cea: cmd.cea,
    ctag: ctag,
    csize: cmd.csize,
    cch: 0
};

typedef struct {
    RequestTag      rtag;
    PSLResponseCode response;
    Int#(9)         rcredits;
} Response deriving(Bits,FShow);


interface CmdBufClientPort#(numeric type brlat);
    method ActionValue#(RequestTag)         putcmd(TagSpecifier tagreq,CmdWithoutTag cmd);
    interface Get#(Response)                response;

    interface PSLBufferInterface            buffer;
endinterface

interface CacheCmdBuf#(numeric type n,numeric type brlat);
    // provides a server to each of its clients
    interface Vector#(n,CmdBufClientPort#(brlat))   client;

    interface Client#(CacheCommand,CacheResponse)   psl;
    interface AFUBufferInterface#(brlat)            pslbuff;
endinterface


/** CmdBuf is a command buffer which arbitrates between multiple competing clients who wish to issue commands.
 * Implements a fixed-priority arbiter, with highest priority given to client 0.
 * Each client may attempt to put a command without a tag. If successful, the ActionValue will fire, returning the tag.
 *
 * When a command response or buffer request arrives, it is forwarded back to the appropriate requestor.
 *
 * NOTE: Currently throws a whole lot of compile warnings unfortunately
 *
 *
 *  ntags       Number of available tags (manages tags 0..ntags-1)
 *
 * TODO: Handle error responses appropriately
 */


module mkCmdBuf#(Integer ntags)(CacheCmdBuf#(n,brlat))
    provisos (
        NumAlias#(natag,8),
        NumAlias#(naclient,TLog#(n)),      // maximum number of clients
        Add#(1,__some,brlat),
        Alias#(UInt#(4),clientIndex),
        Bits#(RequestTag,nbtag));

    Bool showBufferWrites=True;
    Bool showBufferReads=True;
    Bool showCommands=True;

    HCons#(MemSynthesisStrategy,HNil) syn = hCons(AlteraStratixV,hNil);

    // keep track of which client issued which command
    MultiReadLookup#(nbtag,clientIndex)         tagClientMap <- mkMultiReadZeroLatencyLookup(syn,3,ntags);

    // wire carries responses with client index and response
    Reg#(Maybe#(Tuple2#(clientIndex,Response))) pslResponse <- mkDReg(tagged Invalid);


    // tag manager keeps track of which tags are available
    // Bypass = True (same-tag unlock->lock in single cycle) causes big problems meeting timing
    ResourceManager#(nbtag) tagMgr <- mkResourceManager(ntags,False,False);

    FIFO#(CacheCommand) oCmd <- mkPipelineFIFO;

    Vector#(n,CmdBufClientPort#(brlat)) clientP;


	Reg#(Maybe#(BufferWrite))						bwReq    <- mkDReg(tagged Invalid);
	Reg#(Maybe#(clientIndex))						bwClient <- mkDReg(tagged Invalid);

    RWire#(Tuple2#(clientIndex,BufferReadRequest))  brWire <- mkRWire;
    Wire#(Bit#(512))                                brData <- mkWire;

    Reg#(Vector#(brlat,Maybe#(clientIndex)))        brClDelay <- mkReg(replicate(tagged Invalid));

    (* fire_when_enabled, no_implicit_conditions *)
    rule brlatDelay;
        brClDelay <= shiftInAt0(
            brClDelay,
            case (brWire.wget) matches
                tagged Valid { .cl, .* }:   tagged Valid cl;
                tagged Invalid:             tagged Invalid;
            endcase);
    endrule

	// Delay unlock command
	// Found in simulation that commands were able to be issued with a given tag before seeing their completion
	// Was wasting time with Paged, leading to a tag being reissued and re-flushed

	Wire#(RequestTag) rTagToUnlock <- mkDelayWire(2);

	rule doUnlock;
		tagMgr.unlock(rTagToUnlock);			// implicit condition: rTagToUnlock has value
	endrule

    RWire#(RequestTag) specificTagToLock <- mkRWire;
    let pwTagLocked <- mkPulseWire;

    rule doLockSpecificTag if (specificTagToLock.wget matches tagged Valid .v);
        tagMgr.lock(v);
        pwTagLocked.send;
    endrule

    rule checkSpecificLockSuccess if (specificTagToLock.wget matches tagged Valid .v);
        dynamicAssert(pwTagLocked,"specificTagToLock was asserted, but failed to lock the tag");
    endrule


    if (showBufferWrites)
        rule showBufferWrite if (bwReq matches tagged Valid .v);
            $display($time," INFO: CmdBuf received buffer write for client %d: ",bwClient.Valid,fshow(v));
            dynamicAssert(isValid(bwClient),"Buffer write received but no client specified");
        endrule




	Vector#(n,PulseWire) inhibit <- replicateM(mkPulseWire);

    for(Integer i=0;i<valueOf(n);i=i+1)
    begin
        clientP[i] = interface CmdBufClientPort;
            // all of the putcmd methods conflict so use PulseWire to enforce schedule order
            // implicit condition: tagMgr returns a tag
			// note the explicit condition only stops i if i-1 goes, however the scheduler does the rest
            method ActionValue#(RequestTag) putcmd(TagSpecifier tagreq,CmdWithoutTag cmd) if (!inhibit[i]);
				if (i < valueOf(n)-1)
					inhibit[i+1].send;


                RequestTag t;

                if (tagreq matches tagged SpecificTag .tag)
                begin
                    t = tag;
                    specificTagToLock.wset(tag);
//                    dynamicAssert(tagStatus[tag].free,"Requested to issue command with specific tag, but tag is busy");
                end
                else
                    t <- tagMgr.nextAvailable.get;

                // store command and indicate which client originated it
                dynamicAssert(t < fromInteger(ntags),"Invalid tag specified");
                tagClientMap.write(truncate(t),fromInteger(i));

                // enq command to output
                oCmd.enq(bindCommandToTag(t,cmd));

                return t;
            endmethod

            interface Get response;
                method ActionValue#(Response) get if (pslResponse matches tagged Valid { .cl, .resp } &&& cl == fromInteger(i));
                    return resp;
                endmethod
            endinterface

            interface PSLBufferInterface buffer;
                interface ClientU writedata;
                    interface ReadOnly request;
                        method BufferReadRequest _read if (brWire.wget matches tagged Valid { .cl, .br } &&& cl == fromInteger(i)) = br;
                    endinterface

                    interface Put response;
                        method Action put(Bit#(512) brdata);
                            dynamicAssert(last(brClDelay) matches tagged Valid .cl &&& cl == fromInteger(i) ? True : False,
                                "Client responded to buffer read request out of turn");
                            brData <= brdata;

                            if(showBufferReads)
                                $display($time," INFO: Buffer read returned data %X",brdata);
                        endmethod
                    endinterface
                endinterface

                // forward buffer writes if client is selected
                interface ReadOnly readdata;
                    method BufferWrite _read if (bwClient matches tagged Valid .cl &&& cl == fromInteger(i)) = bwReq.Valid;
                endinterface
            endinterface
        endinterface;
    end

    interface Vector client = clientP;

    interface Client psl;
        interface Get request = toGet(oCmd);

        interface Put response;
            method Action put(CacheResponse resp);
                dynamicAssert(resp.rtag < fromInteger(ntags),"Invalid tag specified");

                // steer towards the requesting client whether the downstream module consumes it or not
                let cl <- tagClientMap.lookup[0](truncate(resp.rtag));
                pslResponse <= tagged Valid tuple2(cl, Response { rtag: resp.rtag, response: resp.response, rcredits: resp.rcredits });

                // this is just a reg, so OK
				rTagToUnlock <= resp.rtag;
            endmethod
        endinterface
    endinterface

    interface AFUBufferInterface pslbuff;
        interface ServerAFL writedata;
            interface Put request;
                method Action put(BufferReadRequest br);
                    // look up which client made the request, forward to the wire
                    let cl <- tagClientMap.lookup[1](truncate(br.brtag));
                    brWire.wset(tuple2(cl,br));
                endmethod
            endinterface

            interface ReadOnly response;
                method Bit#(512) _read = brData;
            endinterface
        endinterface

        interface Put readdata;
            method Action put(BufferWrite bw);
                let cl <- tagClientMap.lookup[2](truncate(bw.bwtag));
				bwClient <= tagged Valid cl;
				bwReq    <= tagged Valid bw;
            endmethod
        endinterface
    endinterface
endmodule

endpackage
