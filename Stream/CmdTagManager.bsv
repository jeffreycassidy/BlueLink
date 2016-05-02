package CmdTagManager;

import PSLTypes::*;
import Vector::*;
import FIFO::*;
import SpecialFIFOs::*;
import ProgrammableLUT::*;
import DReg::*;

import AFU::*;
import ClientServerU::*;

import ResourceManager::*;
import SynthesisOptions::*;

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


/** User data provided during .issue() is presented back during buffer reads/writes and completions.
 *
 */

// interface presented to downstream clients
interface CmdTagManagerClientPort#(type userDataT);
    method ActionValue#(RequestTag)                                     issue(CmdWithoutTag cmd,userDataT ud);
    method Tuple2#(CacheResponse,userDataT)                             response;

    interface ClientU#(Tuple2#(BufferReadRequest,userDataT),Bit#(512))  writedata;
    interface ReadOnly#(Tuple2#(BufferWrite,userDataT))                 readdata;
endinterface


// interface
interface CmdTagManagerUpstream#(numeric type brlat);
    interface ClientU#(CacheCommand,CacheResponse)      command;
    interface AFUBufferInterface#(brlat)                buffer;
endinterface



/** Command tag manager tracks the status of command tags and grants them when available to a single client port.
 * It also keeps track of user-provided data that goes along with the command and presents that data with any buffer reads/writes
 * and command responses.
 *
 * All paths through the module are combinational (no added latency)
 * The bit size of the data should be kept small as timing is critical.
 */


module [ModuleContext#(ctxT)] mkCmdTagManager#(Integer ntags)(
        Tuple2#(
            CmdTagManagerUpstream#(brlat),          // upstream AFU-like interface
            CmdTagManagerClientPort#(userDataT)))   // downstream interface presented to client
    provisos (
        NumAlias#(nbtag,8),
        Bits#(userDataT,nbu),
        Bits#(RequestTag,nbtag),
        Gettable#(ctxT,SynthesisOptions));

    // OLD-STYLE (uses regs/ALMs to track tag status and allows parallel access to all tag status)
    // tag manager keeps track of which tags are available
    // Bypass = True (same-tag unlock->lock in single cycle) causes big problems meeting timing
    //ResourceManager#(nbtag) tagMgr <- mkResourceManager(ntags,False,False);

    // NEW-STYLE using a FIFO to track only the next available tag (parallel status access is not available)
    // Disallow bypass, as it introduces a dependency from ha_rvalid through to .issue CAN_FIRE
    // Alternatively, could register the command response before the module
    ResourceManagerSF#(UInt#(6)) tagMgr <- mkResourceManagerFIFO(64,False);

    // client data LUT: hold data provided when command is issued and send back to client with buffer reads
    MultiReadLookup#(nbtag,userDataT) userDataLUT <- mkMultiReadZeroLatencyLookup(3,ntags);

    // passthrough wires
    Wire#(CacheCommand) oCmd <- mkWire;
    Wire#(Tuple2#(CacheResponse,userDataT)) afuResp <- mkWire;
    Wire#(Tuple2#(BufferWrite,userDataT)) bwIn <- mkWire;
    Wire#(Tuple2#(BufferReadRequest,userDataT)) brReq <- mkWire;
    Wire#(Bit#(512)) brResp <- mkWire;

    // Pipe the user data LUT write 1 clock (PSL won't turn a reply around in <= 1 cycle)
    Reg#(Maybe#(Tuple2#(RequestTag,userDataT))) userDataLUTWrite <- mkDReg(tagged Invalid);
    rule writeUserDataLUT if (userDataLUTWrite matches tagged Valid { .tag, .ud });
        userDataLUT.write(tag,ud);
    endrule

    return tuple2(
    interface CmdTagManagerUpstream;
        interface ClientU command;
            interface Put response;
                method Action put(CacheResponse resp);
                    if (resp.response != Done)
                        $display($time, " ERROR: mkCmdTagManager received fault response ",fshow(resp));
                    let ud <- userDataLUT.lookup[2](resp.rtag);
                    afuResp <= tuple2(resp,ud);
                    tagMgr.unlock(truncate(resp.rtag));
                endmethod
            endinterface

            interface ReadOnly request = toReadOnly(oCmd);
        endinterface

        interface AFUBufferInterface buffer;
            interface ServerAFL writedata;
                interface Put request;
                    method Action put(BufferReadRequest br);
                        let ud <- userDataLUT.lookup[0](br.brtag);
                        brReq <= tuple2(br,ud);
                    endmethod
                endinterface

                interface ReadOnly response = toReadOnly(brResp);
            endinterface
            interface Put readdata;
                method Action put(BufferWrite bw);
                    let ud <- userDataLUT.lookup[1](bw.bwtag);
                    bwIn <= tuple2(bw,ud);
                endmethod
            endinterface
        endinterface
    endinterface,
    
    interface CmdTagManagerClientPort;
        method ActionValue#(RequestTag) issue(CmdWithoutTag cmd,userDataT ud);
            let tagi <- tagMgr.nextAvailable.get;
            RequestTag tag = extend(tagi);
            userDataLUTWrite <= tagged Valid tuple2(tag,ud);
            oCmd <= bindCommandToTag(cmd,tag);
            return tag;
        endmethod

        method Tuple2#(CacheResponse,userDataT) response = afuResp;

        interface ClientU writedata;
            interface ReadOnly request = toReadOnly(brReq);
            interface Put response = toPut(asIfc(brResp));
        endinterface
        interface ReadOnly readdata = toReadOnly(bwIn);
    endinterface
    );
endmodule

endpackage
