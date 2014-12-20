package DedicatedAFU;

import StmtFSM::*;
import PSLTypes::*;
import Connectable::*;
import Convenience::*;
import ClientServerFL::*;
import DReg::*;

//interface DedicatedAFU;
//endinterface

typedef union tagged {
    void        Done;
    UInt#(64)   Error;
} AFUReturn deriving(Eq,FShow,Bits);

interface DedicatedAFUNoParity#(type wed_t,numeric type brlat);
    // holds the work element descriptor
    interface SegmentedReg#(wed_t,2,512,6)              wedreg;

    interface ClientU#(CacheCommand,CacheResponse)      command;
    interface AFUBufferInterface#(brlat)                buffer;
    interface ServerARU#(MMIOCommand,MMIOResponse)      mmio;

    method Action parity_error_jobcontrol;
    method Action parity_error_bufferread;
    method Action parity_error_bufferwrite;
    method Action parity_error_mmio;
    method Action parity_error_response;

    // Task control
    method Action                   start;
    method ActionValue#(AFUReturn)  retval;
    method Bool                     done;

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
} Status deriving(Eq,Bits,FShow);

module mkDedicatedAFUNoParity#(Bool pargen,Bool parcheck,DedicatedAFUNoParity#(wed_t,brlat) afu)(AFU#(brlat));

    Reg#(Status)                st <- mkReg(Unknown);
    Reg#(Bool)                  start_next <- mkDReg(False);

    Wire#(EAddress64)           jea_in <- mkWire;

    Wire#(CacheCommand)         master_cmd <- mkWire;

    PulseWire pw_rst <- mkPulseWire;
    PulseWire pw_done <- mkPulseWire;
    PulseWire pw_wed_done <- mkPulseWire;

    Stmt master = seq
        // Handle reset
        st <= Resetting;

        afu.rst.start;
        await(afu.rst.done);

        // Ready, wait for EA to start
        st <= Ready;
        pw_done.send;

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

            // and we're done
            pw_done.send;
        endaction
        
        $display($time,": INFO - DedicatedAFU completed");
    endseq;

    let masterfsm <- mkFSM(master);

    rule startrst if (pw_rst);
        masterfsm.abort;
        start_next <= True;
    endrule

    rule startmaster if (start_next);
        masterfsm.start;
    endrule

    Wire#(CacheCommand) cmd <- mkWire;

    rule ping if (st matches tagged ReadWED .ea);
        $display($time,": INFO - In ReadWED state (",fshow(ea),") issuing command ",fshow(master_cmd));
        cmd <= master_cmd;
        $display($time,": INFO - Issuing WED read command ",fshow(master_cmd));
    endrule

    rule passcmd;
        if (st == Running)
            cmd <= afu.command.request;
        else
        begin
            $display($time,": ERROR - DedicatedAFU received unexpected command from AFU while in status ",fshow(st));
            $display($time,"    details: ",fshow(afu.command.request));
        end
    endrule

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

                        Running:        afu.command.response.put(cr);
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
        interface ServerFL writedata;
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

            interface Get response;
                method ActionValue#(DWordWiseOddParity512) get;
                    let o <- afu.buffer.writedata.response.get;
                    return make_parity_struct(pargen,o);
                endmethod
            endinterface
        endinterface

        interface Put readdata;
            method Action put(BufferWriteWithParity bwp);
                if (parity_maybe(parcheck,bwp) matches tagged Valid .bw)
                    case (st) matches
                        tagged ReadWED .*:                         // intercept buffer writes during WED read
                            afu.wedreg.writeseg(bw.bwad,bw.bwdata);
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
                if (st != Running)
                begin
                    $display($time,": ERROR - DedicatedAFU received MMIO command while not running (state ",fshow(st),")");
                    $display($time,"    details: ",fshow(mmiop));
                end
                else if (parity_maybe(parcheck,mmiop) matches tagged Valid .mmio)
                    afu.mmio.request.put(mmio);
                else
                begin
                    afu.parity_error_mmio;
                    $display($time,": ERROR - DedicatedAFU received MMIO command with invalid parity, notifying afu");
                    $display($time,"    details: ",fshow(mmiop));
                end
            endmethod
        endinterface

        interface ReadOnly response;
            method DataWithParity#(MMIOResponse,OddParity) _read = make_parity_struct(pargen,afu.mmio.response);
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

    method Bool tbreq = False;
    method Bool yield = False;

    method AFU_Status status = AFU_Status {
        running:    case (st) matches
                        tagged Running: True;
                        tagged ReadWED .*: True;
                        default: False;
                    endcase,
        done:       pw_done,
        errcode:    case (st) matches
                        tagged Error .e:    e;
                        default:            0;
                    endcase
    };

    method AFU_Description description = AFU_Description {
        brlat: fromInteger(valueOf(brlat)-1),
        lroom: ?,
        pargen: pargen,
        parcheck: parcheck
    };
endmodule

endpackage
