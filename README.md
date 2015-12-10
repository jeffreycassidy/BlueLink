BlueLink
========

Bluespec SystemVerilog library for use of the IBM Coherent Accelerator-Processor Interface (CAPI).
The current version provides a thin wrapper over the Verilog interface provided by IBM, along with type definitions to make
interfacing easier.

The DedicatedAFU wrapper simplifies interfacing by taking care of config-space MMIO, WED read, and status output. It also registers
the command inputs to meet timing. The afu2host example was synthesized and run in hardware, meeting timing and functioning
correctly.

By writing an AFU which conforms to the DedicatedAFU#(brlat) interface, you can get started quickly and easily. See the afu2host
example described below.


Dependencies
------------

* (optional) Systemsim, the IBM POWER8 functional simulator (for Tcl-based interactive simulation)
    Tested with version 1.0-2 Build 10:00:31 Oct 29 2014
    Available ftp://public.dhe.ibm.com/software/server/powerfuncsim/p8/packages/v1.0-2

* The IBM PSL Simulation Environment (PSLSE) to provide the afu_driver library
    Available http://github.com/ibm-capi/pslse
    Tested with commit 95cb43474ab1d3af129c1ae68a281446f4f8df5f (needed modifications to parsing of pslse_server.dat)

* The Bluespec Compiler bsc
    Note: only Verilog simulation is currently supported due to the Verilog/VPI code provided by IBM

* ModelSim (tested on Altera Starter Edition 10.3c)


Installation notes
------------------

To make the core library Bluespec Object (.bo) files, type 'make' in the Core/ folder.
For simulation of the PSL, you must build PSLSE (see dependencies above) and set the AFU_DRIVER environment variable to point
to the location of the AFU driver file from PSLSE. You will also need to compile the Verilog files user PSLVerilog/.

Once the core files are made, you can proceed to Examples/ and compile the examples using the instructions there.

NOTE: The new version of Systemsim requires GLIBC v >2.15, which is not yet standard on some Linux distros (incl Debian Wheezy).
For Debian Wheezy, the problem can be solved by installing GLIBC 2.19 from Sid (you must edit your dpkg sources.list), though
that broke ModelSim's GUI (at least if using Altera edition; solution was to use two VMs).



Environment setup
-----------------

The following environment variables and files can influence the package/demo function

PSLSE_CXL_DIR       | Where the libcxl.so and #include files are found for the simulation libcxl
PSLSE_ROOT          | The root pslse directory

LD_LIBRARY_PATH     | Needs to contain the path to Bluespec/lib/VPI/g++4 and libcxl.so
capi_env.tcl        | Does some setup for the Modelsim simulation


BLUESPECDIR         | The path with the Bluespec libraries (eg /opt/Bluespec/lib)
BLUELINKDIR         | The root path for the BlueLink library



Outstanding issues
------------------

* Parity generation for buffer reads/writes is not timed correctly since the spec has a lag in it between the valid and parity
presentation


Examples
========

afu2host
--------

This AFU just writes a counter back to host memory, and provides a few simple AFU registers to confirm correct WED read.

After installing pslse, it can be run by entering the BlueLink folder, then running:

make test-afu2host

which will compile the necessary bluespec libraries, AFU code, host code, and launch Modelsim.


