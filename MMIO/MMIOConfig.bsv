package MMIOConfig;

import PSLTypes::*;
import MMIO::*;
import Reserved::*;
import Vector::*;
import DefaultValue::*;
import DReg::*;

/***********************************************************************************************************************************
 * MMIO config-space definitions as per CAPI user guide v1.2
 *
 */


typedef enum { 
    DedicatedProcess = 16'h0010,
	Invalid = 16'hAAAA
} ProgrammingModel deriving(Bits);

typedef struct {
    UInt#(16)           num_ints_per_process;
    UInt#(16)           num_of_processes;
    UInt#(16)           num_of_afu_CRs;
    ProgrammingModel    req_prog_model;
} CfgReg00 deriving(Bits);

typedef ReservedZero#(64)   CfgReg08;
typedef ReservedZero#(64)   CfgReg10;
typedef ReservedZero#(64)   CfgReg18;

typedef struct {
    ReservedZero#(8)    resv;
    UInt#(56)           afu_cr_len;
} CfgReg20 deriving(Bits);

typedef struct {
    UInt#(64)           afu_cr_offset;
} CfgReg28 deriving(Bits);

typedef struct {
    ReservedZero#(6)    resv;
    Bool                per_process_psa_required;
    Bool                psa_required;
    UInt#(56)           per_process_psa_length;
} CfgReg30 deriving(Bits);

typedef struct {
    UInt#(64)           per_process_psa_offset;
} CfgReg38 deriving(Bits);

typedef struct {
    ReservedZero#(8)    resv;
    UInt#(56)           afu_eb_len;
} CfgReg40 deriving(Bits);

typedef struct {
    UInt#(64)           afu_eb_offset;
} CfgReg48 deriving(Bits);




/***********************************************************************************************************************************
 * AFUConfigVector specifies conversion from a config description to a dword vector
 * 
 */

typeclass AFUConfigVector#(type t,numeric type len)  provisos (DefaultValue#(t)) dependencies (t determines len);
    function Vector#(len,Bit#(64)) toConfigVector(t cfg);
endtypeclass



/***********************************************************************************************************************************
 * Instance for dedicated process mode
 *
 */ 

typedef struct {
    UInt#(16) num_ints;
    UInt#(16) num_of_afu_crs;
    UInt#(56) afu_cr_len;
    UInt#(64) afu_cr_offset;
    Bool      psa_required;
    UInt#(56) afu_eb_len;
    UInt#(64) afu_eb_offset;
} DedicatedProcessConfig;


instance DefaultValue#(DedicatedProcessConfig); 
    function DedicatedProcessConfig defaultValue = DedicatedProcessConfig {
        num_ints: 0,
        num_of_afu_crs: 0,
        afu_cr_len: 0,
        afu_cr_offset: 0,
        psa_required: True,
        afu_eb_len: 0,
        afu_eb_offset: 0 };
endinstance


instance AFUConfigVector#(DedicatedProcessConfig,len) provisos (NumAlias#(10,len));

    function Vector#(len,Bit#(64)) toConfigVector(DedicatedProcessConfig cfg);
        Vector#(len,Bit#(64)) mmCfgReg = replicate(0);

        mmCfgReg[0] = pack(CfgReg00 {
                num_ints_per_process: cfg.num_ints,
                num_of_processes: 1,
                num_of_afu_CRs: cfg.num_of_afu_crs,
                req_prog_model: DedicatedProcess });

        mmCfgReg[4] = pack(CfgReg20 {
            afu_cr_len: cfg.afu_cr_len });

        mmCfgReg[5] = pack(CfgReg28 {
            afu_cr_offset: cfg.afu_cr_offset });

        mmCfgReg[6] = pack(CfgReg30 {
            per_process_psa_required: False,
            psa_required: cfg.psa_required,
            per_process_psa_length: 0 });

        mmCfgReg[7] = pack(CfgReg38 {
            per_process_psa_offset: 0 });

        mmCfgReg[8] = pack(CfgReg40 {
            afu_eb_len: cfg.afu_eb_len });

        mmCfgReg[9] = pack(CfgReg48 {
            afu_eb_offset: cfg.afu_eb_offset });

        return mmCfgReg;
    endfunction
endinstance




/***********************************************************************************************************************************
 *
 * mkMMIOStaticConfig(config_t cfg)
 *
 * Static (compile-time constant) configuration registers
 *
 * An instance of AFUConfigVector#(config_t,len) specifies then conversion of the config_t input struct to an output register map.
 * It supports both word and dword reads. Writes are a no-op with ACK sent.
 * 
 * This module is unbuffered. The user will likely need to register input and/or output to meet timing.
 * 
 */

module mkMMIOStaticConfig#(config_t cfg)(Server#(MMIORWRequest,MMIOResponse)) provisos (AFUConfigVector#(config_t,len));
    Vector#(len,Bit#(64)) cfgReg = toConfigVector(cfg);

    RWire#(MMIORWRequest) mmCfgReq <- mkRWire;
    RWire#(MMIOResponse)  ow <- mkRWire;
    Reg#(Maybe#(MMIOResponse)) o <- mkDReg(tagged Invalid);

    rule makeResponse if (mmCfgReq.wget matches tagged Valid .req);
        $display($time," INFO: request received ",fshow(req));
        MMIOResponse resp = case (req) matches
            tagged DWordRead { index: .dwi }: tagged DWordData cfgReg[dwi];
            tagged WordRead  { index: .wi  }: tagged WordData (wi%2==1 ? upper(cfgReg[wi>>1]) : lower(cfgReg[wi>>1]));
            default: WriteAck;
        endcase;
        $display($time," INFO: Response should be ",fshow(resp));
        o <= tagged Valid resp;
    endrule

    interface Put request;
        method Action put(MMIORWRequest req);
            $display($time," INFO: mkMMIOStaticConfig received request ",fshow(req));
            mmCfgReq.wset(req);
        endmethod
    endinterface

    interface Get response;
        method ActionValue#(MMIOResponse) get if (o matches tagged Valid .v);
            $display($time,"INFO: response is ",fshow(v));
            return v;
        endmethod
    endinterface
endmodule

endpackage
