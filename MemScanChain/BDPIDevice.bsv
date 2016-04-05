package BDPIDevice;

import StmtFSM::*;
import RevertingVirtualReg::*;

// Pointer types (BDPIDevice* and BDPIPort* in C++)
typedef UInt#(64) DevicePtr;
typedef UInt#(64) PortPtr;


/** BDPIDevice is meant to work with the C++ class of the same name.
 */

interface BDPIDevice;
	method Action init;
	method Action close;

    // set to True after device's tick method has been called (can use to sequence method calls appropriately)
	method Bool tickHasOccurred;

	method ActionValue#(PortPtr) getPortPtr(UInt#(8) portNum);
endinterface


// IMPORTANT NOTE: If the BDPIDeviceFactoryRegistry and BDPIDeviceFactory are in different library (.so) files, then 
// lazy symbol binding in the linker may cause failure to register the factory prior to a call to the registry.
// To solve the problem, a function or symbol needs to be accessed in the device factory's library.

// create/close a device from the BDPIDeviceFactoryRegistry Singleton
import "BDPI" function ActionValue#(PortPtr)    bdpi_createDeviceFromFactory(String devstr,String argstr,argT argdata)
    provisos (Bits#(argT,nb));

import "BDPI" function Action 					bdpi_deviceClose(DevicePtr dev);

// function to communicate a clock tick to the device; should be called before any device methods
import "BDPI" function Action 					bdpi_deviceTick(DevicePtr dev,Bit#(64) t);

// gets a pointer to the named device port
import "BDPI" function ActionValue#(PortPtr) 	bdpi_deviceGetPort(DevicePtr dev,UInt#(8) portNum);



/** Wrapper around the C++ BDPIDevice class. It holds the pointer, provides for initialization, and stimulates the device with
 * clock ticks.
 *
 *      first:      Action to run before initializing (see notes above re: library lazy binding)
 *      initFunc:   Function to get the device pointer
 *      autoInit:   If true, always initializes post-reset
 */

module mkBDPIDevice#(
        function Action first,
        function ActionValue#(DevicePtr) initFunc,
        Bool autoInit)
    (BDPIDevice);

    // Device pointer
    //  [0] R <none> / W init
    //  [1] R methods / W close
	Reg#(Maybe#(DevicePtr)) devicePtrInternal[2] <- mkCReg(2,tagged Invalid);

	let initFSM <- mkOnce(
		action
            first;
			let p <- initFunc;
			devicePtrInternal[0] <= tagged Valid p;
		endaction);

	rule doAutoInit if (autoInit);
		initFSM.start;
	endrule


	let pwTick <- mkPulseWire;

	// devPtr wire carries implicit conditions that pointer is valid and clock tick has occurred
	Wire#(DevicePtr) devPtr <- mkWire;
	rule doClockTick if (devicePtrInternal[1] matches tagged Valid .p);
		let t <- $time;
		bdpi_deviceTick(p,t);
		pwTick.send;
		devPtr <= p;
	endrule

	method Action init if (!isValid(devicePtrInternal[1])) = initFSM.start;

	method Action close;
		devicePtrInternal[1] <= tagged Invalid;
		bdpi_deviceClose(devPtr);                   // implicit condition: valid device pointer
	endmethod

	method ActionValue#(PortPtr) getPortPtr(UInt#(8) pnum);
		let pp <- bdpi_deviceGetPort(devPtr,pnum);  // implicit condition: valid device pointer
		return pp;
	endmethod

	method Bool tickHasOccurred = pwTick;

endmodule

endpackage
