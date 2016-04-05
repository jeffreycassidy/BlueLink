package Ticker;

// IMPORTANT NOTE: If the BDPIDeviceFactoryRegistry and BDPIDeviceFactory are in different library (.so) files, then 
// lazy symbol binding in the linker may cause failure to register the factory prior to a call to the registry.
// To solve the problem, a function or symbol needs to be accessed in the device factory's library.

// This function serves that purpose for Ticker.

import "BDPI" function Action init_Ticker();

endpackage
