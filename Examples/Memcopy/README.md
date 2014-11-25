Compiling/Running Memcopy
=========================

1. Compile core library in BlueLink/Core (just 'make')
2. make mkMemcopyTB.v to compile Bluespec code into Verilog (requires Bluespec Compiler)
3. Launch ModelSim and source 'memcopy_vsim.tcl'
4. Use 'com' to compile
5. Use 'sim' to simulate
6. After starting the simulation, AFU driver will wait to connect to the server, so must run systemsim with memcopy_mambo.tcl
(the p8memcpy.sh script is provided to do this for you in a separate X window)


Note: you may need to set environment variable CAPI_AFU_DRIVER and CAPI_MAMBO_PATH
