package DedicatedAFU;

import AFU::*;
import StmtFSM::*;
import PSLTypes::*;

import FIFOF::*;
import FIFO::*;

import MMIO::*;
import MMIOConfig::*;

interface DedicatedAFUNoParity#(type wed_t,numeric type brlat);
    // holds the work element descriptor
    interface SegReg#(wed_t,2,512)                      wedreg;

    interface ClientU#(CacheCommand,CacheResponse)      command;
    interface AFUBufferInterface#(brlat)                buffer;
    interface Server#(MMIORWRequest,MMIOResponse)       mmio;

    method Action parity_error_jobcontrol;
    method Action parity_error_bufferread;
    method Action parity_error_bufferwrite;
    method Action parity_error_mmio;
    method Action parity_error_response;

    // Task control
    method Action                   start;
    method ActionValue#(AFUReturn)  retval;

    // reset
    interface FSM                   rst;
endinterface

typedef union tagged {
    void        Unknown;
    void        Resetting;
    void        Ready;
    EAddress64  ReadWED;
    void        Running;
    void        Done;
    UInt#(64)   Error;
} DedicatedAFUStatus deriving(Eq,Bits,FShow);

module mkDedicatedAFUNoParity#(Bool pargen,Bool parcheck,DedicatedAFUNoParity#(wed_t,brlat) afu)(AFU#(brlat));

    Reg#(DedicatedAFUStatus)                st <- mkReg(Unknown);

    Wire#(EAddress64)           jea_in <- mkWire;

    Wire#(CacheCommand)         master_cmd <- mkWire;

    FIFO#(void) startReq <- mkFIFO1;

    PulseWire pw_rst <- mkPulseWire;
    PulseWire pwDone <- mkPulseWire;
    PulseWire pw_wed_done <- mkPulseWire;

    Stmt master = seq
        // Handle reset
        st <= Resetting;
        $display($time," INFO: DedicatedAFU entered reset");

        afu.rst.start;
        await(afu.rst.done);

        // Ready, wait for EA to start
        st <= Ready;
        pwDone.send;

        // Await jea (implicit condition on wire), read WED
        action
            st <= tagged ReadWED jea_in;
            $display($time,": INFO - DedicatedAFU entered ReadWED state, ea=",fshow(jea_in));
        endaction

        noAction;

        master_cmd <= CacheCommand { ctag: 0, cch: 0, com: Read_cl_s, cea: st.ReadWED, csize: 128, cabt: Strict };

        await(pw_wed_done);

        // Run state machine
        st <= Running;

        afu.start;

        action
            let res <- afu.retval;

            case (res) matches
                tagged Done:        st <= Done;
                tagged Error .e:    st <= tagged Error e;
                default:            $display($time,": ERROR - DedicatedAFU received invalid result code ",fshow(res));
            endcase

        endaction

        // and we're done
		action
	        pwDone.send;
    	    $display($time,": INFO - DedicatedAFU completed");
		endaction

    endseq;

    let masterfsm <- mkFSM(master);

    rule abortMaster if (pw_rst);
        $display($time,": DedicatedAFU received reset and is aborting master FSM");
        masterfsm.abort;
    endrule

    rule enqStart if (pw_rst);
        startReq.enq(?);
        $display($time,": DedicatedAFU received reset and is enqing startReq");
    endrule

    rule startMaster;
        masterfsm.start;
        startReq.deq;
        $display($time,": DedicatedAFU starting master FSM");
    endrule

    Wire#(CacheCommand) cmd <- mkWire;

    (* preempts="(ping,passcmd),bad" *)

    rule ping if (st matches tagged ReadWED .ea);
        $display($time,": INFO - In ReadWED state (",fshow(ea),") issuing command ",fshow(master_cmd));
        cmd <= master_cmd;
        $display($time,": INFO - Issuing WED read command ",fshow(master_cmd));
    endrule

    rule passcmd if (st == Running);
        cmd <= afu.command.request;
    endrule

    rule bad;
        $display($time,": ERROR - DedicatedAFU received unexpected command from AFU while in status ",fshow(st));
        $display($time,"    details: ",fshow(afu.command.request));
    endrule

    Server#(MMIORWRequest,MMIOResponse) mmCfg <- mkMMIOStaticConfig(
        DedicatedProcessConfig {
            num_ints: 0,
            num_of_afu_crs: 0,
            afu_cr_len: 0,
            afu_cr_offset: 0,
            psa_required: True,
            afu_eb_len: 0,
            afu_eb_offset: 0
        });

    Bool mmioAcceptPSA = case (st) matches
        Running:            True;
        tagged ReadWED .*:  True;
        default:            False;
    endcase;

    ServerARU#(MMIOCommand,MMIOResponse) mmSplit <- mkMMIOSplitter(mmCfg,afu.mmio,mmioAcceptPSA);

    FIFOF#(CacheResponse) afuresp <- mkGFIFOF1(True,False);

    mkConnection(toGet(afuresp),afu.command.response);

    interface ClientU command;
        interface ReadOnly request;
            method CacheCommandWithParity _read = make_parity_struct(pargen,cmd);
        endinterface

        interface Put response;
            method Action put(CacheResponseWithParity crp);
                if (parity_maybe(parcheck,crp) matches tagged Valid .cr)
                    case (st) matches
                        tagged ReadWED .*:
                            if (cr.rtag == 0 && cr.response == Done)
                                pw_wed_done.send;
                            else
                            begin
                                $display($time,": ERROR - DedicatedAFU received unexpected command response while reading WED");
                                $display($time,"    details: ",fshow(crp));
                            end

                        Running:        afuresp.enq(cr);
                        default:        $display($time,": ERROR - DedicatedAFU received command response while not running (status ",fshow(st),")");
                        endcase
                else
                begin
                    $display($time,": ERROR - DedicatedAFU received command response with invalid parity");
                    $display($time,"    details: ",fshow(crp));
                    afu.parity_error_response;
                end
            endmethod
        endinterface
    endinterface

    interface AFUBufferInterfaceWithParity buffer;
        interface ServerAFL writedata;
            interface Put request;  
                method Action put(BufferReadRequestWithParity brp);
                    if (parity_maybe(parcheck,brp) matches tagged Valid .br)
                        afu.buffer.writedata.request.put(br);
                    else
                    begin
                        $display($time,": ERROR - DedicatedAFU received buffer read request with invalid parity, notifying AFU");
                        $display($time,"    details: ",fshow(brp));
                        afu.parity_error_bufferread;
                    end
                endmethod
            endinterface

            interface ReadOnly response;
                method DWordWiseOddParity512 _read = make_parity_struct(pargen,afu.buffer.writedata.response);
            endinterface
        endinterface

        interface Put readdata;
            method Action put(BufferWriteWithParity bwp);
                if (parity_maybe(parcheck,bwp) matches tagged Valid .bw)
                    case (st) matches
                        tagged ReadWED .*:                         // intercept buffer writes during WED read
                            afu.wedreg.seg[bw.bwad] <= bw.bwdata;
                        Running:                            // pass through when running
                            afu.buffer.readdata.put(bw);                            
                        default:                            // should not receive requests here
                            $display($time,": ERROR - DedicatedAFU received buffer write while in status ",fshow(st));
                    endcase
                else
                begin
                    $display($time,": ERROR - DedicatedAFU received buffer write with invalid parity");
                    $display($time,"    details: ",fshow(bwp));
                    afu.parity_error_bufferwrite;
                end
            endmethod
        endinterface
    endinterface

    interface ServerARU mmio;
        interface Put request;
            method Action put(MMIOCommandWithParity mmiop);
                if (parity_maybe(parcheck,mmiop) matches tagged Valid .mmreq)
                    mmSplit.request.put(mmreq);
                else
                begin
                    afu.parity_error_mmio;
                    $display($time,": ERROR - DedicatedAFU received MMIO command with invalid parity, notifying afu");
                    $display($time,"    details: ",fshow(mmiop));
                end
            endmethod
        endinterface

        interface ReadOnly response;
            method DataWithParity#(MMIOResponse,OddParity) _read = make_parity_struct(pargen,mmSplit.response);
        endinterface
    endinterface

    interface Put control;
        method Action put(JobControlWithParity jcp);
            if (parity_maybe(parcheck,jcp) matches tagged Valid .jc)
                case (jc) matches
                    tagged JobControl { opcode: Start,    jea: .jea  }:   jea_in <= jea;
                    tagged JobControl { opcode: Reset,    jea: .*    }:   pw_rst.send;
                    tagged JobControl { opcode: Timebase, jea: .* }:   $display($time,": DedicatedAFU doesn't support timebase");
                    default:            $display($time,": DedicatedAFU doesn't know what to do with opcode ",fshow(jc.opcode)," [",fshow(pack(jc.opcode)),"]");
                endcase
            else
                afu.parity_error_jobcontrol;
        endmethod
    endinterface

    interface AFUStatus status;
        method Bool tbreq = False;
        method Bool jyield = False;
        method Bool jrunning = case (st) matches
            tagged Running: True;
            tagged ReadWED .*: True;
            default: False;
        endcase;

        method Bool jcack=False;

        method Bool jdone = pwDone;
        method UInt#(64) jerror = case (st) matches
            tagged Error .e:    e;
            default:            0;
        endcase;
    endinterface

    method Bool paren = pargen;

endmodule

endpackage
