package DedicatedAFU;

import Assert::*;
import AFU::*;
import StmtFSM::*;
import PSLTypes::*;

import MMIO::*;
import MMIOConfig::*;

import Vector::*;
import Endianness::*;

import FIFOF::*;


/** mkDedicatedAFUWrapper simplifies AFU design
 *
 * Services provided: MMIO config space handling, WED read, status-flag management, tieoffs of unused ports
 * MMIO is also made into a standard Server interface with proper get/put semantics including implicit conditions.
 */


/** The interface to be provided by a DedicatedAFU to be wrapped */

interface DedicatedAFU#(numeric type brlat);
    method Action wedwrite(UInt#(6) i,Bit#(512) val);

    interface ClientU#(CacheCommand,CacheResponse)      command;
    interface AFUBufferInterface#(brlat)                buffer;
    interface Server#(MMIORWRequest,MMIOResponse)       mmio;

    // Reset control
    method Action                   rst;
    method Bool                     rdy;

    // Task control
    method Action                   start(EAddress64 ea,UInt#(8) croom);
    method ActionValue#(AFUReturn)  retval;
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
    Reg#(DedicatedAFUStatus)    st <- mkReg(Unknown);

    Wire#(EAddress64)           jeaIn <- mkWire;

    Wire#(CacheCommand)         wedCmd <- mkWire;

    FIFOF#(CacheResponse)        wedResponse <- mkGFIFOF1(True,False);

    Reg#(UInt#(8))              croom <- mkReg(0);

    let                         pwDone <- mkPulseWire;




    /** Hardware wrapper throws a hard reset (BSV RST_N) at powerup and whenver a reset command is received
     * This FSM starts immediately following reset deassertion.
     */

    Stmt master = seq
        // Start AFU reset
        action
            $display($time," INFO: DedicatedAFU starting reset");
            st <= Resetting;
            afu.rst;
        endaction

        // Wait for client AFU reset to finish
        await(afu.rdy);
        action
            $display($time," INFO: DedicatedAFU reset done");
            st      <= Ready;
        endaction

        noAction;
        pwDone.send;

        // Await jea (implicit condition on wire), read WED
        action
            st <= tagged ReadWED jeaIn;
            $display($time," INFO: DedicatedAFU entered ReadWED state, ea=",fshow(jeaIn));
        endaction

        // Issue WED read, wait for completion
        wedCmd <= CacheCommand { ctag: 0, cch: 0, com: Read_cl_na, cea: st.ReadWED, csize: 128, cabt: Strict };

        action
            wedResponse.deq;
            if (wedResponse.first.response == Done)
            begin
                $display($time, " INFO: WED read completed");
                afu.start(st.ReadWED,croom);
                st <= Running;
            end
            else
            begin
                $display($time," ERROR: Dedicated AFU failed to read WED, with response ",fshow(wedResponse.first));
                st <= tagged Error 64'hffffffffffffffff;
                dynamicAssert(False,"DedicatedAFU failed to read WED");
            end
        endaction


        // Wait for AFU to terminate
        action
            let res <- afu.retval;
            case (res) matches
                tagged Done:
                    action
                        st <= Done;
                        $display($time," INFO: DedicatedAFU finished");
                    endaction
                tagged Error .e:
                    action
                        st <= tagged Error e;
                        $display($time," INFO: DedicatedAFU terminated with error code %016X",e);
                    endaction
            endcase
        endaction

        // and we're done (wait 1 cycle after deasserting jrunning via st above)
        noAction;
	    pwDone.send;
    endseq;


    // let master run once per reset
    let masterfsm <- mkFSM(master);
    let startMaster <- mkOnce(masterfsm.start);

    rule startMasterOnReset;
        startMaster.start;
    endrule




    ////// Command issuance

    Wire#(CacheCommand) cmd <- mkWire;

    rule issueWEDReadCommand if (st matches tagged ReadWED .ea);
        cmd <= wedCmd;
    endrule

    rule issueAFUCommand if (st == Running);
        cmd <= afu.command.request;
    endrule




    ////// MMIO

    Server#(MMIORWRequest,MMIOResponse) mmCfg <- mkMMIOStaticConfig(
        DedicatedProcessConfig {
            num_ints:       0,
            num_of_afu_crs: 0,
            afu_cr_len:     0,
            afu_cr_offset:  0,
            psa_required:   True,
            afu_eb_len:     0,
            afu_eb_offset:  0
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
            method CacheCommand _read = cmd;
        endinterface

        interface Put response;
            method Action put(CacheResponse cr);
                case (st) matches
                    tagged ReadWED .ea:
                        action
                            dynamicAssert(cr.rtag==0,"Dedicated AFU received unexpected response during WED read");
                            wedResponse.enq(cr);
                        endaction

                    tagged Running:
                        afu.command.response.put(cr);

                    default:
                        action
                            $display($time," ERROR: Dedicated AFU received command response while not running (status ",fshow(st),")");
                            dynamicAssert(False,"DedicatedAFU received a response while not running or in WED Read");
                        endaction
                endcase
            endmethod
        endinterface
    endinterface

    interface AFUBufferInterface buffer;
        interface ServerAFL writedata;
            interface Put request;  
                method Action put(BufferReadRequest br);
                    dynamicAssert(st==Running,"Dedicated AFU received a buffer read request while not running");
                    afu.buffer.writedata.request.put(br);
                endmethod
            endinterface

            interface ReadOnly response = afu.buffer.writedata.response;
        endinterface

        interface Put readdata;
            method Action put(BufferWrite bw);
                case (st) matches
                    tagged ReadWED .*:                  // intercept buffer writes during WED read
                        afu.wedwrite(bw.bwad,bw.bwdata);
                    Running:                            // pass through when running
                        afu.buffer.readdata.put(bw);                            
                    default:                            // should not receive requests here
                        $display($time," ERROR: DedicatedAFU received buffer write while in status ",fshow(st));
                endcase
            endmethod
        endinterface
    endinterface

    interface ServerARU mmio = mmSplit;

    interface Put control;
        method Action put(JobControl jc);
            case (jc.opcode) matches
                Start:
                    action
                        jeaIn <= jc.jea;
                        croom <= jc.croom;
                    endaction
                Reset:      noAction;                // wrapper will throw a hard reset anyway
                Timebase:
                    dynamicAssert(False,"DedicatedAFU doesn't handle timebase");
                default:
                    dynamicAssert(False,"Invalid job control word");
            endcase
        endmethod
    endinterface

    interface AFUStatus status;
        method Bool tbreq   = False;
        method Bool jyield  = False;
        method Bool jcack   = False;

        method Bool jrunning = case (st) matches
            tagged Running:     True;
            tagged ReadWED .*:  True;
            default:            False;
        endcase;

        method Bool jdone = pwDone;

        method UInt#(64) jerror = case (st) matches
            tagged Error .e:    e;
            default:            0;
        endcase;
    endinterface
endmodule

endpackage
