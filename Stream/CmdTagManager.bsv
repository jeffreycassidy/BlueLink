package CmdTagManager;

import PSLTypes::*;
import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;

import HList::*;

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

typeclass ToReadOnly#(type t,type ifc);
    function ReadOnly#(t) toReadOnly(ifc i);
endtypeclass

instance ToReadOnly#(t,t);
    function ReadOnly#(t) toReadOnly(t i) = interface ReadOnly;
        method t _read = i;
    endinterface;
endinstance



function CacheCommand bindCommandToTag(CmdWithoutTag cmd,RequestTag ctag) = CacheCommand {
    com: cmd.com,
    cabt: cmd.cabt,
    cea: cmd.cea,
    ctag: ctag,
    csize: cmd.csize,
    cch: 0
};


// interface presented to downstream clients
interface CmdTagManagerClientPort;
    method ActionValue#(RequestTag)                     issue(CmdWithoutTag cmd);
    method CacheResponse                                response;

    interface ClientU#(BufferReadRequest,Bit#(512))     writedata;
    interface ReadOnly#(BufferWrite)                    readdata;
endinterface


// interface
interface CmdTagManagerUpstream#(numeric type brlat);
    interface ClientU#(CacheCommand,CacheResponse)      command;
    interface AFUBufferInterface#(brlat)                buffer;
endinterface


module mkCmdTagManager#(Integer ntags)(
        Tuple2#(
            CmdTagManagerUpstream#(brlat),      // upstream AFU-like interface
            CmdTagManagerClientPort))           // downstream interface presented to client
    provisos (
        NumAlias#(nbtag,8),
        Bits#(RequestTag,nbtag));

    // tag manager keeps track of which tags are available
    // Bypass = True (same-tag unlock->lock in single cycle) causes big problems meeting timing
    ResourceManager#(nbtag) tagMgr <- mkResourceManager(ntags,False,False);

    // passthrough wires
    Wire#(CacheCommand) oCmd <- mkWire;
    Wire#(CacheResponse) afuResp <- mkWire;
    Wire#(BufferWrite) bwIn <- mkWire;
    Wire#(BufferReadRequest) brReq <- mkWire;
    Wire#(Bit#(512)) brResp <- mkWire;

    return tuple2(
    interface CmdTagManagerUpstream;
        interface ClientU command;
            interface Put response;
                method Action put(CacheResponse resp);
                    if (resp.response != Done)
                        $display($time, " ERROR: mkCmdTagManager received fault response ",fshow(resp));
                    afuResp <= resp;
                    tagMgr.unlock(resp.rtag);
                endmethod
            endinterface

            interface ReadOnly request = toReadOnly(oCmd);
        endinterface

        interface AFUBufferInterface buffer;
            interface ServerAFL writedata;
                interface Put request = toPut(asIfc(brReq));
                interface ReadOnly response = toReadOnly(brResp);
            endinterface
            interface Put readdata = toPut(asIfc(bwIn));
        endinterface
    endinterface,
    
    interface CmdTagManagerClientPort;
        method ActionValue#(RequestTag) issue(CmdWithoutTag cmd);
            let tag <- tagMgr.nextAvailable.get;
            oCmd <= bindCommandToTag(cmd,tag);
            return tag;
        endmethod

        method CacheResponse response = afuResp;

        interface ClientU writedata;
            interface ReadOnly request = toReadOnly(brReq);
            interface Put response = toPut(asIfc(brResp));
        endinterface
        interface ReadOnly readdata = toReadOnly(bwIn);
    endinterface
    );
endmodule

endpackage
