package CmdBuf;

import PSLTypes::*;
import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;
import RevertingVirtualReg::*;
import BLProgrammableLUT::*;

import AFU::*;
import ClientServerU::*;

import ResourceManager::*;

import Assert::*;

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
    method ActionValue#(RequestTag)         putcmd(CmdWithoutTag cmd);
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
        NumAlias#(ntag,16),
        NumAlias#(natag,4),
        Add#(1,__some,brlat),
        Bits#(RequestTag,nbtag));

    // last issued command for each tag, and the client who issued the command
    Lookup#(natag,CmdWithoutTag)    tagCmdHist      <- mkZeroLatencyLookup(ntags);
    Lookup#(natag,UInt#(4))         tagClientMap    <- mkZeroLatencyLookup(ntags);      // duplicate for multiple lookups
    Lookup#(natag,UInt#(4))         tagClientMap1   <- mkZeroLatencyLookup(ntags);
    Lookup#(natag,UInt#(4))         tagClientMap2   <- mkZeroLatencyLookup(ntags);

    // wire carries responses with client index and response
    Wire#(Tuple2#(UInt#(natag),Response)) respWire <- mkWire;

    // tag manager keeps track of which tags are available
    ResourceManager#(nbtag) tagMgr <- mkResourceManager(ntags,False,True);

    FIFO#(CacheCommand) oCmd <- mkPipelineFIFO;

    Vector#(n,Reg#(Bool)) fixedPrioritySequence <- replicateM(mkRevertingVirtualReg(True));

    Vector#(n,CmdBufClientPort#(brlat)) clientP;

    Wire#(Tuple2#(UInt#(natag),BufferWrite))  bwWire <- mkWire;
    RWire#(Tuple2#(UInt#(natag),BufferReadRequest))  brWire <- mkRWire;
    Wire#(Bit#(512))                            brData <- mkWire;

    Reg#(Vector#(brlat,Maybe#(UInt#(natag))))   brClDelay <- mkReg(replicate(tagged Invalid));

    (* fire_when_enabled, no_implicit_conditions *)
    rule brlatDelay;
        brClDelay <= shiftInAt0(
            brClDelay,
            case (brWire.wget) matches
                tagged Valid { .cl, .* }:   tagged Valid cl;
                tagged Invalid:             tagged Invalid;
            endcase);
    endrule

    for(Integer i=0;i<valueOf(n);i=i+1)
    begin
        clientP[i] = interface CmdBufClientPort;
            // all of the putcmd methods conflict so use RevertReg to enforce schedule order
            // implicit condition: tagMgr returns a tag
            method ActionValue#(RequestTag) putcmd(CmdWithoutTag cmd) if (fixedPrioritySequence[i]);
                if (i > 0)
                    fixedPrioritySequence[i-1] <= True;

                // get the tag
                let t <- tagMgr.nextAvailable.get;

                // store command and indicate which client originated it
                dynamicAssert(t < fromInteger(ntags),"Invalid tag specified");
                tagCmdHist.write(truncate(t),cmd);
                tagClientMap.write(truncate(t),fromInteger(i));
                tagClientMap1.write(truncate(t),fromInteger(i));
                tagClientMap2.write(truncate(t),fromInteger(i));

                // enq command to output
                oCmd.enq(bindCommandToTag(t,cmd));

                return t;
            endmethod

            interface Get response;
                method ActionValue#(Response) get if (respWire matches { .cl, .resp } &&& cl == fromInteger(i)) =
                    actionvalue return resp; endactionvalue;
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
                        endmethod
                    endinterface
                endinterface

                // forward buffer writes if client is selected
                interface ReadOnly readdata;
                    method BufferWrite _read if (bwWire matches { .cl, .bw } &&& cl == fromInteger(i)) = bw;
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
                let cl <- tagClientMap.lookup(truncate(resp.rtag));
                respWire <= tuple2(cl, Response { rtag: resp.rtag, response: resp.response, rcredits: resp.rcredits });

                // update internal state
                case (resp.response) matches
                    Done:       tagMgr.unlock(resp.rtag);
                    default:
                    action
                        tagMgr.unlock(resp.rtag);
                        $display($time," WARNING: freeing tag %d after response ",resp.rtag,fshow(resp));
//                        dynamicAssert(False,"Invalid response type, don't know how to deal with it");
                    endaction
                endcase
            endmethod
        endinterface
    endinterface

    interface AFUBufferInterface pslbuff;
        interface ServerAFL writedata;
            interface Put request;
                method Action put(BufferReadRequest br);
                    // look up which client made the request, forward to the wire
                    let cl <- tagClientMap2.lookup(truncate(br.brtag));
                    brWire.wset(tuple2(cl,br));
                endmethod
            endinterface

            interface ReadOnly response;
                method Bit#(512) _read = brData;
            endinterface
        endinterface

        interface Put readdata;
            method Action put(BufferWrite bw);
                let cl <- tagClientMap1.lookup(truncate(bw.bwtag));
                bwWire <= tuple2(cl, bw);
            endmethod
        endinterface
    endinterface
endmodule

endpackage
