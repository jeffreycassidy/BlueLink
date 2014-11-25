#!/bin/bash

# Launches the Mambo functional simulator in a separate window
echo "Launching separate X Terminal for mambo"

if [ -z "$CAPI_MAMBO_PATH" ]; then echo "You may need to set CAPI_MAMBO_PATH"; fi
if [ -z "$CAPI_AFU_HOST" ]; then echo "You may need to set CAPI_AFU_HOST"; fi
if [ -z "$CAPI_AFU_PORT" ]; then echo "You may need to set CAPI_AFU_PORT"; fi

# use env to control environment when multiple instances are installed
env -i DISPLAY=$DISPLAY CAPI_AFU_HOST=$CAPI_AFU_HOST CAPI_AFU_PORT=$CAPI_AFU_PORT LD_LIBRARY_PATH=$CAPI_MAMBO_PATH/lib PATH=/bin:/usr/bin:$CAPI_MAMBO_PATH/bin:$CAPI_MAMBO_PATH/run/pegasus \
	xterm -hold -e "power8 -n -f memcopy_mambo.tcl"&
