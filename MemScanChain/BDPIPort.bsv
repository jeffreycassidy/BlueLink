package BDPIPort;

import BDPIDevice::*;
import StmtFSM::*;
import RevertingVirtualReg::*;

export BDPIPort,mkBDPIPort,Status;

//// Need to match C++ defs
typedef enum { Ready=0, Wait=1, End=255 } Status deriving(Bits,Eq);

import "BDPI" function ActionValue#(Status) bdpi_portGetStatus(PortPtr portPtr);
import "BDPI" function ActionValue#(dataT)	bdpi_portGetReadData(PortPtr portPtr) provisos (Bits#(dataT,nd));
import "BDPI" function Action				bdpi_portPutWriteData(PortPtr portPtr,dataT o) provisos (Bits#(dataT,nd));
import "BDPI" function Action				bdpi_portClose(PortPtr portPtr);
//// end C++


interface BDPIPort#(type readDataT,type writeDataT);
	method Status 					status;

	method ActionValue#(readDataT)	read;
	method Action					write(writeDataT data);

	method Bool 					done;           // True if C++ device indicates end of stream

	method Action 					close;
endinterface




/** Wrapper for a BDPIPort C++ object attached to a BDPIDevice object.
 * It handles initialization by waiting until the device is initialized, then calling the getPortPtr method.
 * 
 * For reads and writes, it checks the device's clock tick indicator to sequence method calls appropriately,
 * and checks port status to provide implicit conditions.
 *
 *      dev     The parent device
 *      portNum Port number to request
 *      onInit  Handler to call after initialization
 */


module mkBDPIPort#(BDPIDevice dev,Integer portNum,function Action onInit(PortPtr p))(BDPIPort#(readDataT,writeDataT))
	provisos(Bits#(readDataT,nr),Bits#(writeDataT,nw));

    // the BDPIPort* object
    //  [0] R <none> / W init
    //  [1] R methods / W close

	Reg#(Maybe#(PortPtr)) portPtrInternalReg[2] <- mkCReg(2,tagged Invalid);


    // initialization logic (implicit conditions on dev.getPortPtr)
	let getPortPtrFSM <- mkOnce(
		action
			let p <- dev.getPortPtr(fromInteger(portNum));
			portPtrInternalReg[0] <= tagged Valid p;
            onInit(p);
		endaction);

	rule getPortPtr;
		getPortPtrFSM.start;
	endrule



	Wire#(Status) st <- mkWire;                         // port status
	Wire#(PortPtr) portPtr <- mkWire;                   // valid if port pointer valid and clock tick has been sent
    Reg#(Bool) rvrClose <- mkRevertingVirtualReg(True); // force close to schedule last

	rule getPointer if (portPtrInternalReg[1] matches tagged Valid .v &&& dev.tickHasOccurred);
		portPtr <= v; 

		let st_ <- bdpi_portGetStatus(portPtr);
		st <= st_;
	endrule

	method ActionValue#(readDataT) read if (st == Ready && rvrClose);
		let o <- bdpi_portGetReadData(portPtr);
		return o;
	endmethod

	method Action write(writeDataT o) if (st == Ready && rvrClose);
		bdpi_portPutWriteData(portPtr,o);
	endmethod

	method Action close;
        bdpi_portClose(portPtr);        // implicit condition on portptr
        rvrClose <= False;              // force scheduling after read/write
    endmethod

	method Status status = st;

	method Bool done = st==End;
	
endmodule


endpackage
