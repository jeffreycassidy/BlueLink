// Provides AFUHardware#(brlat), a port-exact wrapper for the AFU's expected RTL footprint (plus RST_N)

import AFU::*;
import PSLTypes::*;
import Parity::*;
import Assert::*;
import Clocks::*;


typeclass CAPIHardwareWrappable#(type hwifc, type bsvifc);
    module mkCAPIHardwareWrapper#(bsvifc b)(hwifc);
endtypeclass


/** AFUHardware#(brlat)
 *
 */


interface AFUHardware#(numeric type brlat);
    (* prefix="" *)
    interface AFUHardwareCommand        hwcommand;

    (* prefix="" *)
    interface AFUHardwareBuffer#(brlat) hwbuffer;

    (* prefix="" *)
    interface AFUHardwareMMIO           hwmmio;

    (* prefix="" *)
    interface AFUHardwareControl        hwcontrol;

    (* prefix="" *)
    interface AFUHardwareStatus         hwstatus;

    (* prefix="",always_enabled *)
    method UInt#(4) ah_brlat;

    (* prefix="",always_enabled *)
    method Bool     ah_paren;

    (* prefix="",always_enabled *)
    method Action pslAttributes(UInt#(8) ha_croom);
endinterface

instance CAPIHardwareWrappable#(AFUHardware#(brlat),AFUWithParity#(brlat));
    module mkCAPIHardwareWrapper#(AFUWithParity#(brlat) bsvifc)(AFUHardware#(brlat));
        let c <- mkCAPIHardwareWrapper(bsvifc.command);
        let b <- mkCAPIHardwareWrapper(bsvifc.buffer);
        let m <- mkCAPIHardwareWrapper(bsvifc.mmio);
        let t <- mkCAPIHardwareWrapper(bsvifc.control);
        let s <- mkCAPIHardwareWrapper(bsvifc.status);

        interface AFUHardwareCommand hwcommand = c;
        interface AFUHardwareBuffer  hwbuffer = b;
        interface AFUHardwareMMIO    hwmmio = m;
        interface AFUHardwareControl hwcontrol = t; 
        interface AFUHardwareStatus  hwstatus = s;

        method Bool ah_paren = bsvifc.attributes.pargen;
        method UInt#(4) ah_brlat = case (valueOf(brlat)) matches
            2: 1;
            4: 3;
        endcase;

        method Action pslAttributes(UInt#(8) ha_croom) = bsvifc.pslAttributes(PSLAttributes { croom: ha_croom });
    endmodule
endinstance



interface AFUHardwareCommand;
    (* prefix="" *)
    interface AFUHardwareCommandRequest     hwrequest;
    (* prefix="" *)
    interface AFUHardwareCommandResponse    hwresponse;
endinterface

instance CAPIHardwareWrappable#(AFUHardwareCommand,ClientU#(CacheCommandWithParity,CacheResponseWithParity));
    module mkCAPIHardwareWrapper#(ClientU#(CacheCommandWithParity,CacheResponseWithParity) bsvifc)(AFUHardwareCommand);
        let req  <- mkCAPIHardwareWrapper(asIfc(bsvifc.request));
        let resp <- mkCAPIHardwareWrapper(bsvifc.response);
        interface AFUHardwareCommandRequest  hwrequest  = req; 
        interface AFUHardwareCommandResponse hwresponse = resp;
    endmodule
endinstance



interface AFUHardwareCommandRequest;
    (* ready="ah_cvalid" *)
    method PSLCommand   ah_com;

    (* always_ready *)
    method Bit#(1)      ah_compar;

    (* always_ready *)
    method PSLTranslationOrdering  ah_cabt;

    (* always_ready *)
    method EAddress64   ah_cea;

    (* always_ready *)
    method Bit#(1)      ah_ceapar;

    (* always_ready *)
    method UInt#(16)    ah_cch;

    (* always_ready *)
    method UInt#(12)    ah_csize;

    (* always_ready *)
    method UInt#(8)     ah_ctag;

    (* always_ready *)
    method Bit#(1)      ah_ctagpar;

endinterface

instance CAPIHardwareWrappable#(AFUHardwareCommandRequest,ReadOnly#(CacheCommandWithParity));
    module mkCAPIHardwareWrapper#(ReadOnly#(CacheCommandWithParity) bsvifc)(AFUHardwareCommandRequest);
        Wire#(CacheCommandWithParity) always_ready_wrapper <- mkDWire(?);

        mkConnection(bsvifc,toPut(asIfc(always_ready_wrapper)));
        
        method PSLCommand               ah_com      = bsvifc.com.data;
        method Bit#(1)                  ah_compar   = always_ready_wrapper.com.parityval.pbit;
        method PSLTranslationOrdering   ah_cabt     = always_ready_wrapper.cabt;
        method EAddress64               ah_cea      = always_ready_wrapper.cea.data;
        method Bit#(1)                  ah_ceapar   = always_ready_wrapper.cea.parityval.pbit;
        method UInt#(16)                ah_cch      = always_ready_wrapper.cch;
        method UInt#(12)                ah_csize    = always_ready_wrapper.csize;
        method UInt#(8)                 ah_ctag     = always_ready_wrapper.ctag.data;
        method Bit#(1)                  ah_ctagpar  = always_ready_wrapper.ctag.parityval.pbit;
    endmodule
endinstance




interface AFUHardwareCommandResponse;
    (* always_ready, enable="ha_rvalid",prefix="" *)
    method Action putCacheResponse(RequestTag ha_rtag,Bit#(1) ha_rtagpar,PSLResponseCode ha_response,Int#(9) ha_rcredits,
        Bit#(2) ha_rcachestate,UInt#(13) ha_rcachepos);
endinterface

instance CAPIHardwareWrappable#(AFUHardwareCommandResponse,Put#(CacheResponseWithParity));
    module mkCAPIHardwareWrapper#(Put#(CacheResponseWithParity) bsvifc)(AFUHardwareCommandResponse);
        method Action putCacheResponse(RequestTag ha_rtag,Bit#(1) ha_rtagpar,PSLResponseCode ha_response,Int#(9) ha_rcredits,
            Bit#(2) ha_rcachestate,UInt#(13) ha_rcachepos) =
                bsvifc.put(CacheResponseWithParity {
                    rtag:           DataWithParity { data: ha_rtag, parityval: OddParity { pbit: ha_rtagpar } },
                    response:       ha_response,
                    rcredits:       ha_rcredits,
                    rcachestate:    ha_rcachestate,
                    rcachepos:      ha_rcachepos
                });
    endmodule
endinstance


interface AFUHardwareBuffer#(numeric type brlat);
    (* prefix="" *)
    interface AFUHardwareBufferRead#(brlat) hwread;

    (* prefix="" *)
    interface AFUHardwareBufferWrite        hwwrite;
endinterface

instance CAPIHardwareWrappable#(AFUHardwareBuffer#(brlat),AFUBufferInterfaceWithParity#(brlat));
    module mkCAPIHardwareWrapper#(AFUBufferInterfaceWithParity#(brlat) bsvifc)(AFUHardwareBuffer#(brlat));
        let r <- mkCAPIHardwareWrapper(bsvifc.writedata);
        let w <- mkCAPIHardwareWrapper(bsvifc.readdata);
        interface AFUHardwareBufferRead hwread = r;
        interface AFUHardwareBufferWrite hwwrite = w;
    endmodule
endinstance

interface AFUHardwareBufferRead#(numeric type brlat);
    (* prefix="" *)
    interface AFUHardwareBufferReadRequest  hwrequest;

    (* always_ready,prefix="" *)
    interface AFUHardwareBufferReadResponse hwresponse;
endinterface

instance CAPIHardwareWrappable#(AFUHardwareBufferRead#(brlat),ServerAFL#(BufferReadRequestWithParity,DWordWiseOddParity512,brlat));
    module mkCAPIHardwareWrapper#(ServerAFL#(BufferReadRequestWithParity,DWordWiseOddParity512,brlat) bsvifc)(AFUHardwareBufferRead#(brlat));
        let req <- mkCAPIHardwareWrapper(bsvifc.request);
        let resp <- mkCAPIHardwareWrapper(asIfc(bsvifc.response));
        interface AFUHardwareBufferReadRequest hwrequest = req; 
        interface AFUHardwareBufferReadResponse hwresponse = resp;
    endmodule
endinstance

interface AFUHardwareBufferReadRequest;
    (* always_ready, enable="ha_brvalid",prefix="" *)
    method Action putBR(RequestTag ha_brtag,Bit#(1) ha_brtagpar,UInt#(6) ha_brad);
endinterface

instance CAPIHardwareWrappable#(AFUHardwareBufferReadRequest,Put#(BufferReadRequestWithParity));
    module mkCAPIHardwareWrapper#(Put#(BufferReadRequestWithParity) bsvifc)(AFUHardwareBufferReadRequest);
        method Action putBR(RequestTag ha_brtag,Bit#(1) ha_brtagpar,UInt#(6) ha_brad) =
            bsvifc.put(BufferReadRequestWithParity {
                brtag: DataWithParity { data: ha_brtag, parityval: OddParity { pbit: ha_brtagpar } },
                brad: ha_brad
            });
    endmodule
endinstance




interface AFUHardwareBufferReadResponse;
    (* always_ready *)
    method Bit#(512)    ah_brdata;

    (* always_ready *)
    method Bit#(8)      ah_brpar;
endinterface

instance CAPIHardwareWrappable#(AFUHardwareBufferReadResponse,ReadOnly#(DWordWiseOddParity512));
    module mkCAPIHardwareWrapper#(ReadOnly#(DWordWiseOddParity512) bsvifc)(AFUHardwareBufferReadResponse);
        Wire#(DWordWiseOddParity512) always_ready_wrapper <- mkDWire(?);

        mkConnection(bsvifc,toPut(asIfc(always_ready_wrapper)));

        method Bit#(512)            ah_brdata   = always_ready_wrapper.data;
        method Bit#(8)              ah_brpar= pack(always_ready_wrapper.parityval.pvec);
    endmodule
endinstance



interface AFUHardwareBufferWrite;
    (* always_ready, enable="ha_bwvalid",prefix="" *)
    method Action putBufferWriteRequest(RequestTag ha_bwtag,Bit#(1) ha_bwtagpar,UInt#(6) ha_bwad,
        Bit#(512) ha_bwdata,Bit#(8) ha_bwpar);
endinterface

instance CAPIHardwareWrappable#(AFUHardwareBufferWrite,Put#(BufferWriteWithParity));
    module mkCAPIHardwareWrapper#(Put#(BufferWriteWithParity) bsvifc)(AFUHardwareBufferWrite);
        method Action putBufferWriteRequest(RequestTag ha_bwtag,Bit#(1) ha_bwtagpar,UInt#(6) ha_bwad,Bit#(512) ha_bwdata,
            Bit#(8) ha_bwpar) =
            bsvifc.put(BufferWriteWithParity {
                bwtag: DataWithParity { data: ha_bwtag, parityval: OddParity { pbit: ha_bwtagpar } },
                bwad:  ha_bwad,
                bwdata: DataWithParity { data: ha_bwdata, parityval: WordWiseParity { pvec: unpack(ha_bwpar) } }
            });
    endmodule
endinstance


interface AFUHardwareMMIO;
    (* prefix="" *)
    interface AFUHardwareMMIORequest  hwrequest;
    (* prefix="" *)
    interface AFUHardwareMMIOResponse hwresponse;
endinterface

instance CAPIHardwareWrappable#(AFUHardwareMMIO,ServerARU#(MMIOCommandWithParity,DataWithParity#(MMIOResponse,OddParity)));
    module mkCAPIHardwareWrapper#(ServerARU#(MMIOCommandWithParity,DataWithParity#(MMIOResponse,OddParity)) bsvifc)(AFUHardwareMMIO);
        let req <- mkCAPIHardwareWrapper(bsvifc.request);
        let resp <- mkCAPIHardwareWrapper(asIfc(bsvifc.response));
        interface AFUHardwareMMIORequest hwrequest = req;
        interface AFUHardwareMMIOResponse hwresponse = resp;
    endmodule
endinstance

interface AFUHardwareMMIORequest;
    (* always_ready,enable="ha_mmval",prefix="" *)
    method Action putMMIO(Bool ha_mmcfg,Bool ha_mmrnw,Bool ha_mmdw,UInt#(24) ha_mmad,Bit#(1) ha_mmadpar,
        Bit#(64) ha_mmdata,Bit#(1) ha_mmdatapar);
endinterface

instance CAPIHardwareWrappable#(AFUHardwareMMIORequest,Put#(MMIOCommandWithParity));
    module mkCAPIHardwareWrapper#(Put#(MMIOCommandWithParity) bsvifc)(AFUHardwareMMIORequest);

        method Action putMMIO(Bool ha_mmcfg,Bool ha_mmrnw,Bool ha_mmdw,UInt#(24) ha_mmad,Bit#(1) ha_mmadpar,
            Bit#(64) ha_mmdata,Bit#(1) ha_mmdatapar);

            let cmd = MMIOCommandWithParity {
                mmcfg: ha_mmcfg,
                mmrnw: ha_mmrnw,
                mmdw:  ha_mmdw,
                mmad:  DataWithParity { data: ha_mmad, parityval: OddParity { pbit: ha_mmadpar } },
                mmdata:DataWithParity { data: ha_mmdata, parityval: OddParity { pbit: ha_mmdatapar } }
            };

            if (ha_mmdw)
                dynamicAssert(ha_mmad % 2 == 0,"Invalid alignment for DWord read");

            if (!ha_mmrnw && !ha_mmdw)
                dynamicAssert(ha_mmdata[31:0] == ha_mmdata[63:32],"High bits != low bits for MMIO word write");

            bsvifc.put(cmd);

        endmethod
    endmodule
endinstance

interface AFUHardwareMMIOResponse;
    (* ready="ah_mmack" *)
    method Bit#(64) ah_mmdata;

    (* always_ready *)
    method Bit#(1) ah_mmdatapar;
endinterface

instance CAPIHardwareWrappable#(AFUHardwareMMIOResponse,ReadOnly#(DataWithParity#(MMIOResponse,OddParity)));
    module mkCAPIHardwareWrapper#(ReadOnly#(DataWithParity#(MMIOResponse,OddParity)) bsvifc)(AFUHardwareMMIOResponse);
        Wire#(Bit#(1)) always_ready_wrapper <- mkDWire(?);

        rule getdata;
            always_ready_wrapper <= bsvifc.parityval.pbit;
        endrule

        method Bit#(64) ah_mmdata = rawBits(bsvifc.data);
        method Bit#(1) ah_mmdatapar = always_ready_wrapper;
    endmodule
endinstance


interface AFUHardwareControl;
    (* always_ready,enable="ha_jval",prefix="" *)
    method Action put(PSLJobOpcode ha_jcom,Bit#(1) ha_jcompar,EAddress64 ha_jea, Bit#(1) ha_jeapar);
endinterface

instance CAPIHardwareWrappable#(AFUHardwareControl,Put#(JobControlWithParity));
    module mkCAPIHardwareWrapper#(Put#(JobControlWithParity) bsvifc)(AFUHardwareControl);
        method Action put(PSLJobOpcode ha_jcom,Bit#(1) ha_jcompar,EAddress64 ha_jea, Bit#(1) ha_jeapar) = 
            bsvifc.put( JobControlWithParity {
                opcode : DataWithParity { data: ha_jcom, parityval: OddParity { pbit: ha_jcompar } },
                jea    : DataWithParity { data: ha_jea,  parityval: OddParity { pbit: ha_jeapar  } }
            });  
    endmodule
endinstance


interface AFUHardwareStatus;
    (* always_ready *)
    method Bool ah_tbreq;

    (* always_ready *)
    method Bool ah_jyield;

    (* always_ready  *)
    method Bool ah_jcack;

    (* always_ready *)
    method UInt#(64) ah_jerror;

    (* always_ready *)
    method Bool ah_jrunning;

    (* always_ready *)
    method Bool ah_jdone;

endinterface

instance CAPIHardwareWrappable#(AFUHardwareStatus,AFUStatus);
    module mkCAPIHardwareWrapper#(AFUStatus bsvifc)(AFUHardwareStatus);
        method Bool ah_tbreq = bsvifc.tbreq;
        method Bool ah_jyield = bsvifc.jyield;

        method Bool ah_jcack = False;
        method Bool ah_jdone = bsvifc.jdone;
        method Bool ah_jrunning = bsvifc.jrunning;
        method UInt#(64) ah_jerror = bsvifc.jerror;

    endmodule
endinstance



/***********************************************************************************************************************************
 * Reset support
 */


// power-on reset controller imported from Verilog
interface POR;
    (* always_ready *)
    method Bool isAsserted;
endinterface

// asserts reset for n cycles after power-on (done in Verilog because BSV doesn't have power-on defaults for anything)
import "BVI" module mkPOR#(Integer n)(POR);
    method orst isAsserted reset_by(no_reset);

    parameter n=n;

    schedule isAsserted CF isAsserted;
endmodule


// module which sends a reset either at power-on or when specifically forced to by its boolean input going high
module mkPowerOnSyncReset#(Bool forceRst)(MakeResetIfc);
    Clock clk <- exposeCurrentClock;
    let autoRst <- mkPOR(2,reset_by noReset);

    MakeResetIfc rstctrl <- mkResetSync(2,False,clk,reset_by noReset);

    rule doRst if (autoRst.isAsserted || forceRst);
        rstctrl.assertReset;
    endrule

    return rstctrl;
endmodule


// this AFU pass-through module sends a pulse when a reset command is received

(* no_default_reset *)

module mkCheckAFUReset#(AFU#(brlat) shim)(Tuple2#(Bool,AFU#(brlat)));
    let isRstCmd <- mkPulseWire(reset_by noReset);

    return tuple2(isRstCmd,interface AFU;
        interface ClientU command = shim.command;
        interface AFUBufferInterface buffer = shim.buffer;
        interface ServerARU mmio = shim.mmio;
        interface Put control;
            method Action put(JobControl jc);
                if (jc.opcode == Reset)             // intercept reset requests and trigger internal reset machinery
                    isRstCmd.send;
                else                                // pass everything else through
                    shim.control.put(jc);
                endmethod
            endinterface
    
            interface AFUStatus status;
                method Bool tbreq = False;
                method Bool jyield = False;

                // gate the status signals when reset is applied; this seems important to PSLSE (have not tested in hw)
                method Bool jrunning = isRstCmd ? False : shim.status.jrunning;
                method Bool jdone = isRstCmd ? False : shim.status.jdone;
                method UInt#(64) jerror = shim.status.jerror;
            endinterface
            
            method attributes = shim.attributes;
            method pslAttributes = shim.pslAttributes;
    endinterface);
endmodule

