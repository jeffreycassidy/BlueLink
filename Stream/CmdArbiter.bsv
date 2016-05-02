package CmdArbiter;

import Vector::*;
import CmdTagManager::*;

import ClientServerU::*;
import ProgrammableLUT::*;
import PSLTypes::*;
import DReg::*;
import GetPut::*;

import SynthesisOptions::*;

/** Priority arbiter which will always grant to client[i] before client[i+1]. As a result, the issue methods schedule in increasing
 * order of client index. Commands are not registered by this module.
 * 
 * Buffer reads/write and command responses are steered to the appropriate originating client. Since buffer reads are latency-
 * critical they are not registered. Buffer writes and command responses are, adding an extra cycle of latency.
 *
 */

module [ModuleContext#(ctxT)] mkCmdPriorityArbiter#(CmdTagManagerClientPort#(userDataT) tagMgr)(Vector#(nPorts,CmdTagManagerClientPort#(userDataT)))
    provisos (
        Alias#(UInt#(4),clientIndex),
        Bits#(userDataT,nbu),
        Bits#(RequestTag,nbRequestTag),
        NumAlias#(brlat,2),
        Gettable#(ctxT,SynthesisOptions));

    Vector#(nPorts,CmdTagManagerClientPort#(userDataT)) clients;

    MultiReadLookup#(nbRequestTag,clientIndex) tagClientMap <- mkMultiReadZeroLatencyLookup(3,64);

    // client indices for the various input ports
    Reg#(Maybe#(Tuple3#(clientIndex,CacheResponse,userDataT))) cmdResponseClient <- mkDReg(tagged Invalid);

    RWire#(clientIndex) brRequestClient <- mkRWire;
    Reg#(Maybe#(Tuple3#(clientIndex,BufferWrite,userDataT))) bwClient <- mkReg(tagged Invalid);
    Reg#(Vector#(brlat,Maybe#(clientIndex))) brRequestClientD <- mkReg(replicate(tagged Invalid));

    rule getClientIndexForCmdResponse;
        let { resp, ud } = tagMgr.response;
        let cl <- tagClientMap.lookup[0](resp.rtag);
        cmdResponseClient <= tagged Valid tuple3(cl,resp,ud);
    endrule

    rule getClientIndexForBufRead;
        let { br, ud } = tagMgr.writedata.request;
        let cl <- tagClientMap.lookup[1](br.brtag);
        brRequestClient.wset(cl);
    endrule

    rule getClientIndexForBufWrite;
        let { bw, ud } = tagMgr.readdata;
        let cl <- tagClientMap.lookup[2](bw.bwtag);
        bwClient <= tagged Valid tuple3(cl,bw,ud);
    endrule

    rule shiftRegForBufReadDelay;
        brRequestClientD <= shiftInAt0(brRequestClientD,brRequestClient.wget);
    endrule


    // the client ports
    function Bool read(PulseWire pw) = pw;

    Vector#(nPorts,PulseWire) pwGrant <- replicateM(mkPulseWire);

    Vector#(nPorts,Bool) clientGrant = map (read,pwGrant);

    Vector#(TAdd#(nPorts,1),Bool) block = scanl(
        ( \|| ) ,
        False,
        clientGrant);

    // allow 1 cycle delay to ease timing into the 3 tagClientMap MLABs
    Reg#(Maybe#(Tuple2#(RequestTag,clientIndex))) tagClientMapWrite <- mkDReg(tagged Invalid);

    rule writeTagClientMap if (tagClientMapWrite matches tagged Valid { .tag, .cl });
        tagClientMap.write(tag,cl);
    endrule


    for(Integer i=0;i<valueOf(nPorts);i=i+1)
    begin
        clients[i] = interface CmdTagManagerClientPort;
            method ActionValue#(RequestTag) issue(CmdWithoutTag cmd,userDataT ud) if (!block[i]);
                pwGrant[i].send;
                let tag <- tagMgr.issue(cmd,ud);

                // delay tagClientMap write by 1 cycle, on the assumption that PSL will not turn around a response in <= 1 cycle
                tagClientMapWrite <= tagged Valid tuple2(tag,fromInteger(i));

//                tagClientMap.write(tag,fromInteger(i));
                return tag;
            endmethod

            method Tuple2#(CacheResponse,userDataT) response 
                if (cmdResponseClient matches tagged Valid { .cl, .resp, .ud } &&& cl == fromInteger(i)) =
                    tuple2(resp,ud);

            interface ClientU writedata;
                interface ReadOnly request;
                    method Tuple2#(BufferReadRequest,userDataT) _read
                        if (brRequestClient.wget matches tagged Valid .cl &&& cl == fromInteger(i))
                            = tagMgr.writedata.request;
                endinterface

                interface Put response;
                    method Action put(Bit#(512) resp) if (last(brRequestClientD) matches tagged Valid .cl &&& cl == fromInteger(i))
                        = tagMgr.writedata.response.put(resp);
                endinterface
            endinterface

            interface ReadOnly readdata;
                method Tuple2#(BufferWrite,userDataT) _read
                    if (bwClient matches tagged Valid { .cl, .bw, .ud } &&& cl == fromInteger(i))
                        = tuple2(bw,ud);
            endinterface
        endinterface;
    end

    return clients;
endmodule

endpackage
