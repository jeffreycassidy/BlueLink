package BDPIDeviceTest;

import BDPIDevice::*;
import StmtFSM::*;

/** Simple testcase that instantiates a C++ Ticker and lets it run for 10 ticks before closing
 */

import Ticker::*;

module mkTB_Ticker10();

    BDPIDevice dut <- mkBDPIDevice(
        init_Ticker,
        bdpi_createDeviceFromFactory("Ticker","foobarticker",32'hdeadbeef),
        True);

    Stmt stim = seq
        repeat(10) noAction;
    endseq;

    mkAutoFSM(stim);
endmodule


/** 
 */

endpackage
