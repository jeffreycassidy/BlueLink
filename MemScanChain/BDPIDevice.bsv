package BDPIDevice;

import StmtFSM::*;

typedef UInt#(64) DevicePtr;
typedef UInt#(64) PortPtr;

interface BDPIDevice;
	method Action init;
	method Action close;

	// wait for this to be true if something needs to happen after the clock tick (eg. port read/write)
	method Bool tickHasOccurred;

	method ActionValue#(PortPtr) getPort(UInt#(8) portNum);
endinterface

import "BDPI" function Action 					bdpi_deviceClose(DevicePtr dev);
import "BDPI" function Action 					bdpi_deviceTick(DevicePtr dev,Bit#(64) t);
import "BDPI" function ActionValue#(PortPtr) 	bdpi_deviceGetPort(DevicePtr dev,UInt#(8) portNum);

module mkDevice#(function ActionValue#(DevicePtr) initFunc,Bool autoInit)(BDPIDevice);
	// Holds the device pointer, should only be 
	Reg#(Maybe#(DevicePtr)) devicePtrInternal <- mkReg(tagged Invalid);

	let pwTick <- mkPulseWire;
	
	let initFSM <- mkOnce(
		action
			let p <- initFunc;
			devicePtrInternal <= tagged Valid p;
		endaction);

	rule doAutoInit if (autoInit);
		initFSM.start;
	endrule

	// devPtr wire carries implicit conditions that pointer is valid and clock tick has occurred
	Wire#(DevicePtr) devPtr <- mkWire;
	rule doClockTick if (devicePtrInternal matches tagged Valid .p);
		let t <- $time;
		bdpi_deviceTick(p,t);
		pwTick.send;
		devPtr <= p;
	endrule

	method Action init if (!isValid(devicePtrInternal) && autoInit);
		initFSM.start;
	endmethod

	method Action close if (isValid(devicePtrInternal));
		devicePtrInternal <= tagged Invalid;
		bdpi_deviceClose(devPtr);
	endmethod

	method ActionValue#(PortPtr) getPort(UInt#(8) pnum) if (isValid(devicePtrInternal));
		let pp <- bdpi_deviceGetPort(devPtr,pnum);
		return pp;
	endmethod

	method Bool tickHasOccurred = pwTick;

endmodule

endpackage
