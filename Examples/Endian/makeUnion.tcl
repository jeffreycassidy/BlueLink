set start 0
set end   256

puts "typedef union tagged {"

for { set i $start } { $i < $end } { incr i  } {
    puts "    // Tag [format "%02X" $i]"
    puts "    [format "void Unused%02X;" $i]"
    puts ""
}
puts "} Union8b deriving(Eq,FShow,Bits);"
