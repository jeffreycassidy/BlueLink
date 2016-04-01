package BDPIPort;

import BDPIDevice::*;

//// Need to match C++ defs
typedef enum { Ready=0, Wait=1, End=255 } Status deriving(Bits,Eq);

import "BDPI" function ActionValue#(Status) bdpi_portGetStatus(PortPtr portPtr);
import "BDPI" function ActionValue#(dataT)	bdpi_portGetReadData(PortPtr portPtr) provisos (Bits#(dataT,nd));
import "BDPI" function Action				bdpi_portPutWriteData(PortPtr portPtr,dataT o) provisos (Bits#(dataT,nd));
import "BDPI" function Action				bdpi_portClose(PortPtr portPtr);

//// end C++

interface BDPIPort#(type dataT);
	method Status 				status;
	method ActionValue#(dataT)	read;
	method Action				write(dataT data);

	method Bool 				done;

	method Action 				close;
endinterface


module mkBDPIPort#(BDPIDevice dev,Integer portNum)(BDPIPort#(dataT))
	provisos(Bits#(dataT,nd));

	Reg#(Maybe#(PortPtr)) portPtrInternalReg <- mkReg(tagged Invalid);

	// portPtr carries implicit conditions: valid port pointer and clock tick has already been sent to the device
	Wire#(PortPtr) portPtr <- mkWire;
	rule getPointer if (portPtrInternalReg matches tagged Valid .v &&& dev.tickHasOccurred);
		portPtr <= v; 
	endrule

	// status depends on clock tick
	Wire#(Status) st <- mkWire;
	
	rule checkStatus;
		let st_ <- bdpi_portGetStatus(portPtr);
		st <= st_;
	endrule

	method ActionValue#(dataT) read if (st == Ready);
		let o <- bdpi_portGetReadData(portPtr);
		return o;
	endmethod

	method Action write(dataT o) if (st == Ready);
		bdpi_portPutWriteData(portPtr,o);
	endmethod

	method Action close = bdpi_portClose(portPtr);

	method Status status = st;

	method Bool done = st==End;
	
endmodule


endpackage
