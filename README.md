BlueLink
========

Bluespec SystemVerilog library for use of the IBM Coherent Accelerator-Processor Interface (CAPI).
The current version provides a thin wrapper over the Verilog interface provided by IBM, along with type definitions to make
interfacing easier.

All interface data structures come in with- and without-parity versions, and FShow instances are provided to facilitate debug.
There is also the SnoopConnection interface which parrots out everything flowing across the connection to stdout.

In the future, I plan to develop and release wrappers which provide successively more convenience to the developer (eg. parity
handling, request-tag management, etc) as well as submodules with more powerful functionality (connections to FPGA Block
RAM/regs/MLABS are just being packaged for release).



Dependencies
------------

* Systemsim, the IBM POWER8 functional simulator
    Tested with version 1.0-2 Build 10:00:31 Oct 29 2014
    Available ftp://public.dhe.ibm.com/software/server/powerfuncsim/p8/packages/v1.0-2

* The IBM PSL Simulation Environment (PSLSE) to provide the afu_driver library
    Available http://github.com/kirkmorrow/pslse
    Tested with commit 60e1ec5cc7

* The Bluespec Compiler bsc
    Note: only Verilog simulation is currently supported due to the Verilog/VPI code provided by IBM

* The BlueLogic package, a collection of handy "glue logic" in Bluespec
    Also available at github.com/jeffreycassidy/BlueLogic



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

The following environment variables can influence the package/demo function

CAPI_AFU_DRIVER  	| Specifies the location of the AFU driver shared library in PSLSE (required for Verilog simulation)
CAPI_AFU_HOST		| AFU hostname (defaults to localhost)
CAPI_AFU_PORT		| AFU port (defaults to 32768)
CAPI_SYSTEMSIM_PATH	| Path to Systemsim root
BLUELOGIC   		| Path to the BlueLogic library (defaults to ../BlueLogic from BlueLink path)
BLUELINK    		| Path to the BlueLink library



Outstanding issues
------------------

* Parity generation for buffer reads/writes is not timed correctly since the spec has a lag in it between the valid and parity
presentation
