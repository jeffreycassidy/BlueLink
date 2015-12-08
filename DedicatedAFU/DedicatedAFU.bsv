package DedicatedAFU;

import Assert::*;
import AFU::*;
import StmtFSM::*;
import PSLTypes::*;

import FIFOF::*;
import FIFO::*;

import MMIO::*;
import MMIOConfig::*;

import DReg::*;

import Vector::*;
import Endianness::*;

/** The interface to be implemented by the wrapped module */

interface DedicatedAFU#(numeric type brlat);
    interface Vector#(2,WriteOnly#(Bit#(512)))          wedwrite;

    interface ClientU#(CacheCommand,CacheResponse)      command;
    interface AFUBufferInterface#(brlat)                buffer;
    interface Server#(MMIORWRequest,MMIOResponse)       mmio;

    // Task control
    method Action                   start;
    method ActionValue#(AFUReturn)  retval;

    // Reset status (True -> complete)
    method Bool rst;
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

module mkDedicatedAFU#(DedicatedAFU#(brlat) afu)(AFU#(brlat));
    Bool pargen = False;                                // True -> wrapper generates parity
    Bool parcheck = False;                              // True -> wrapped checks parity

    Reg#(DedicatedAFUStatus)    st <- mkReg(Unknown);

    Wire#(EAddress64)           jeaIn <- mkWire;

    Wire#(CacheCommand)         wedCmd <- mkWire;

    let pwWedDone <- mkPulseWire;

    Reg#(Bool) pwDoneQ <- mkDReg(False);




    /** Hardware wrapper throws a hard reset (BSV RST_N) at powerup and whenver a reset command is received
     * This FSM starts immediately following reset deassertion. Steps:
     */

    Stmt master = seq
        // Start wrapper reset
        action
            $display($time," INFO: DedicatedAFU wrapper entered reset");
            st <= Resetting;
        endaction

        // Wait for client AFU reset to finish
        action
            await(afu.rst);
            $display($time," INFO: Slave AFU reset done, sending jdone pulse");
            st <= Ready;
            pwDoneQ <= True;
        endaction

        // Await jea (implicit condition on wire), read WED
        action
            st <= tagged ReadWED jeaIn;
            $display($time,": INFO - DedicatedAFU entered ReadWED state, ea=",fshow(jeaIn));
        endaction

        // Issue WED read, wait for completion
        wedCmd <= CacheCommand { ctag: 0, cch: 0, com: Read_cl_na, cea: st.ReadWED, csize: 128, cabt: Strict };
        await(pwWedDone);

        // Start the AFU
        action
            afu.start;
            st <= Running;
        endaction


        // Wait for AFU to terminate
        action
            let res <- afu.retval;

            case (res) matches
                tagged Done:        st <= Done;
                tagged Error .e:    st <= tagged Error e;
                default:            $display($time,": ERROR - DedicatedAFU received invalid result code ",fshow(res));
            endcase
        endaction

        // and we're done (wait 1 cycle after deasserting jrunning via st above)
		action
	        pwDoneQ <= True;
    	    $display($time,": INFO - DedicatedAFU completed and sending done pulse");
		endaction

    endseq;


    // let master run once per reset
    let masterfsm <- mkFSM(master);
    let startMaster <- mkOnce(masterfsm.start);

    rule startMasterOnReset;
        startMaster.start;
    endrule


    ////// Command issuance

    Wire#(CacheCommand) cmd <- mkWire;

    (* mutually_exclusive="issueWEDReadCommand,issueAFUCommand" *)

    rule issueWEDReadCommand if (st matches tagged ReadWED .ea);
        cmd <= wedCmd;
    endrule

    rule issueAFUCommand;
        dynamicAssert(st == Running,"AFU attempted to issue a command while not running");
        cmd <= afu.command.request;
    endrule


    ////// MMIO

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




    //////

    interface ClientU command;
        interface ReadOnly request;
            method CacheCommandWithParity _read = make_parity_struct(pargen,cmd);
        endinterface

        interface Put response;
            method Action put(CacheResponseWithParity crp);
                if (parity_maybe(parcheck,crp) matches tagged Valid .cr)
                    case (st) matches
                        tagged ReadWED .ea:
                            if (cr.rtag == 0)
                            begin
                                if (cr.response == Done)
                                    pwWedDone.send;
                                else
                                begin
                                    $display($time," ERROR: Dedicated AFU failed to read WED, with response");
                                    dynamicAssert(False,"DedicatedAFU failed to read WED");
                                end
                            end
                            else
                            begin
                                $display($time," ERROR: Dedicated AFU received unexpected response for tag %d during WED read",cr.rtag);
                                dynamicAssert(False,"Dedicated AFU received unexpected response");
                            end

                        tagged Running:
                            afu.command.response.put(cr);

                        default:
                        begin
                            $display($time,": ERROR - DedicatedAFU received command response while not running (status ",fshow(st),")");
                            dynamicAssert(False,"DedicatedAFU received a response while not running or in WED Read");
                        end
                    endcase
                else
                begin
                    $display($time,": ERROR - DedicatedAFU received command response with invalid parity");
                    $display($time,"    details: ",fshow(crp));
//                    afu.parity_error_response;
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
//                        afu.parity_error_bufferread;
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
                        tagged ReadWED .*:                  // intercept buffer writes during WED read
                            afu.wedwrite[bw.bwad] <= bw.bwdata;
                        Running:                            // pass through when running
                            afu.buffer.readdata.put(bw);                            
                        default:                            // should not receive requests here
                            $display($time,": ERROR - DedicatedAFU received buffer write while in status ",fshow(st));
                    endcase
                else
                begin
                    $display($time,": ERROR - DedicatedAFU received buffer write with invalid parity");
                    $display($time,"    details: ",fshow(bwp));
//                    afu.parity_error_bufferwrite;
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
//                    afu.parity_error_mmio;
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
                    tagged JobControl { opcode: Start,    jea: .jea  }:   jeaIn <= jea;
                    tagged JobControl { opcode: Reset,    jea: .*    }:   noAction;         // will be caught by the wrapper
                    tagged JobControl { opcode: Timebase, jea: .* }:   $display($time,": DedicatedAFU doesn't support timebase");
                    default:            $display($time,": DedicatedAFU doesn't know what to do with opcode ",fshow(jc.opcode)," [",fshow(pack(jc.opcode)),"]");
                endcase
            else
            begin
                $display($time," ERROR: Parity failure on Job Control interface");
//                afu.parity_error_jobcontrol;
            end
        endmethod
    endinterface

    interface AFUStatus status;
        method Bool tbreq    = False;
        method Bool jyield   = False;
        method Bool jcack=False;

        method Bool jrunning = case (st) matches
            tagged Running:     True;
            tagged ReadWED .*:  True;
            default:            False;
        endcase;

        method Bool jdone = pwDoneQ;

        method UInt#(64) jerror = case (st) matches
            tagged Error .e:    e;
            default:            0;
        endcase;
    endinterface

    method Bool paren = pargen;

endmodule

endpackage
