# This is a modified copy of IBM's memcopy demo driver from the CAPI Demo Kit
# Original (c) Copyright International Business Machines 2014
# Modifications by Jeffrey Cassidy
#

# This script should be run in the Mambo functional simulator to talk to the Verilog AFU simulation

if { [info exists env(CAPI_AFU_HOST)] == 0 } { 
    set host localhost
    puts "Environment variable CAPI_AFU_HOST not set; using default host $host"
} else { set host $env(CAPI_AFU_HOST) }

if { [info exists env(CAPI_AFU_PORT)] == 0 } {
    set port 32768
    puts "Environment variable CAPI_AFU_PORT not set; using default port $port"
} else { set port $env(CAPI_AFU_PORT) }

puts "Connecting to $host:$port"


define dup pegasus PROC
PROC config machine_option/memory_overflow TRUE
PROC config cpus 1
PROC config processor/number_of_threads 8
PROC config enable_pseries_nvram FALSE
PROC config machine_option/NO_ROM TRUE
PROC config machine_option/NO_RAM TRUE
PROC config machine_option/CAPI_XLATE_DISABLE TRUE
# Initialize the systemsim tcl environment
source $env(LIB_DIR)/pegasus/mambo_init.tcl

# Configure and create the simulated machine
define dup $config myconf
myconf config processor_option/CAPI_XLATE FALSE
myconf config processor_option/CAPI_CAIA_SPEC_011 TRUE
#myconf config processor_option/CAPI_CAIA_SPEC_012_ES TRUE
#myconf config processor_option/CAPI_ENABLE_NEW_FEATURES TRUE
define machine myconf mysim

proc get_rand {modulo} {
  set number0 [expr rand()]
  set number0 [lindex [split $number0 .] 1]
  set number0 [string range $number0 1 9]
  set number1 [expr rand()]
  set number1 [lindex [split $number1 .] 1]
  set number1 [string range $number1 1 9]
  append number $number0$number1
  while {[string range $number 0 0] == 0} {
    set number [string range $number 1 end]
  }
  if {$modulo == 0} { return [expr $number & 0xFFFFFFFFFFFFFFFF] }
  return [expr $number % $modulo]
}

## controls verbosity of debug
simdebug set CAPI 1
#simdebug set CAPI_MMIO 1
#simdebug set PSL_FN 1
#simdebug set MEM_REF 1

set bar0 0x1D00000000000
set bar2 0x1D00100000000
set afu_regs [expr {$bar0 + 0x2000000}]

set freq 2000000000

puts "setting seed"
set seed [get_rand 0]
puts "calling expr"
expr srand($seed)

puts "setting wed start"

# select an address for the WED
# does wed address need to be cache aligned?
set wed_start 0x0000000010002e80

mysim capi create $bar2 $bar0 1
mysim capi connect 0 $freq $host $port

set from 0x008CDAB475E75A00
set to   0x009CDAB475E75A00
set size 256
set failed 0

# fill in the WED: 64b source addr, 64b destination addr, 64b size
puts "Initializing WED with from=0x[format %016x $from] to=0x[format %016x $to]"
mysim memory set $wed_start 8 $from
mysim memory set [expr $wed_start + 8] 8 $to
mysim memory set [expr $wed_start + 16] 8 $size

# initialize the source data area to be copied
# might want to initialize area around from address
# might want to initialize area in and around to address
puts "Initializing memory to be copied"
for {set offset 0} {$offset < $size} {incr offset 8} {
  set bytes_left [expr $size - $offset]
  if {$bytes_left < 8} {
    set write_bytes $bytes_left
    set value [get_rand [expr 256*$bytes_left]]
  } else {
    set write_bytes 8
    set value [get_rand 0]
  }
  mysim memory set [expr $from + $offset] $write_bytes $value

  puts "offset $offset: [mysim memory display [expr $from + $offset] $write_bytes]"
}

simdebug set MEM_REF 0
#exit

puts "Initialize PSL_RXCTL croom"
# initialize PSL_RXCTL[croom]
mysim memory set [expr $bar2 + 0x100E0] 8 0x8000000000000000
mysim cycle 20

# this section represents the basic effects of the cxl_afu_open_dev
# and cxl_afu_attach libcxl api calls.  In essense, resetting the AFU
# and then sending the work element descriptor and enabling (starting)
# the AFU 
# First cxl_afu_open_dev establish some OS device file data structures that we don't model here

# Next, cxl_afu_attach sets the WED register in psl and then
# sets the afu enable bit

puts "Resetting AFU"
mysim cycle 10
mysim memory set [expr $bar0 + 0x090] 8 0x0100000000000000
mysim cycle 10

# we should mask control reg to access only RS bits
set test_afu_cntl_a [mysim memory display [expr $bar0 + 0x090] 8]
set test_afu_cntl_a_rs 0x[format %016X [expr $test_afu_cntl_a & 0x0C00000000000000]]
# puts $test_afu_cntl_a_rs

while {$test_afu_cntl_a_rs ne 0x0800000000000000} {
  mysim cycle 1
  set test_afu_cntl_a [mysim memory display [expr $bar0 + 0x090] 8]
  set test_afu_cntl_a_rs 0x[format %016X [expr $test_afu_cntl_a & 0x0C00000000000000]]
  # puts $test_afu_cntl_a_rs
}

puts "Setting WED and sending start (enable) to AFU"
mysim memory set [expr $bar0 + 0x0A0] 8 $wed_start
mysim cycle 1
mysim memory set [expr $bar0 + 0x090] 8 0x1000000000000000
mysim cycle 1

# we should mask control reg to access only ES bits
set test_afu_cntl_a [mysim memory display [expr $bar0 + 0x090] 8]
set test_afu_cntl_a_es 0x[format %016X [expr $test_afu_cntl_a & 0xE000000000000000]]
puts "AFU_CNTL_An_ES: $test_afu_cntl_a_es"

while {$test_afu_cntl_a_es ne 0x8000000000000000} {
  mysim cycle 1
  set test_afu_cntl_a [mysim memory display [expr $bar0 + 0x090] 8]
  set test_afu_cntl_a_es 0x[format %016X [expr $test_afu_cntl_a & 0xE000000000000000]]
  puts "AFU_CNTL_An: $test_afu_cntl_a"
}
mysim cycle 1
puts "Start AFU complete"

# ES will go to 0b000 when complete
while {$test_afu_cntl_a_es eq 0x8000000000000000} {
#  mysim cycle [expr 1 + ($size * 16)]
  mysim cycle 1
  set test_afu_cntl_a [mysim memory display [expr $bar0 + 0x090] 8]
  set test_afu_cntl_a_es 0x[format %016X [expr $test_afu_cntl_a & 0xE000000000000000]]
}

mysim cycle 10


puts "Job complete, checking results"
for {set offset 0} {$offset < $size} {incr offset 8} {
  set read_bytes 8
  set bytes_left [expr $size - $offset]
  if {$bytes_left < 8} {
    set read_bytes $bytes_left
  }
  set from_value [mysim memory display [expr $from + $offset] $read_bytes]
  set to_value [mysim memory display [expr $to + $offset] $read_bytes]
  if {$from_value ne $to_value} {
    puts "ERROR: Expected $from_value Actual $to_value at address 0x[format %016X [expr $to + $offset]]"
    set failed 1
  }
}

set to_value [mysim memory display [expr $from - 1] 1]
if {$to_value != 0} {
  puts "ERROR: Corruption write at 0x[format %016x [expr $from - 1]]"
}
set to_value [mysim memory display [expr $from + $size] 1]
if {$to_value != 0} {
  puts "ERROR: Corruption write at 0x[format %016x [expr $from + $size]]"
}

puts ""
if {$failed == 0} {
  puts "PASSED sort of $size elements with seed $seed"
} else {
  puts "FAILED sort of $size elements with seed $seed"
}


quit
