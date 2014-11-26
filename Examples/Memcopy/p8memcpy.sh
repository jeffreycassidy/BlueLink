#!/bin/bash

# Launches the functional simulator in a separate window
echo "Launching separate X Terminal for Systemsim"

if [ -z "$CAPI_SYSTEMSIM_PATH" ]; then echo "You may need to set CAPI_SYSTEMSIM_PATH"; fi
if [ -z "$CAPI_AFU_HOST" ]; then echo "You may need to set CAPI_AFU_HOST"; fi
if [ -z "$CAPI_AFU_PORT" ]; then echo "You may need to set CAPI_AFU_PORT"; fi

# use env to control environment when multiple instances are installed
env -i DISPLAY=$DISPLAY CAPI_AFU_HOST=$CAPI_AFU_HOST CAPI_AFU_PORT=$CAPI_AFU_PORT LD_LIBRARY_PATH=$CAPI_SYSTEMSIM_PATH/lib PATH=/bin:/usr/bin:$CAPI_SYSTEMSIM_PATH/bin:$CAPI_SYSTEMSIM_PATH/run/pegasus \
	xterm -hold -e "power8 -n -f memcopy_systemsim.tcl"&
