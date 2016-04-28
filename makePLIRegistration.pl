use Cwd;
my $dir = getcwd;

$#ARGV == 0 or die "Needs an argument: output file name";

open OFH,">$ARGV[0]";

print "// Automatically generated file based on contents of $dir\n\n";

my @files = `ls vpi_wrapper_*.h`;

foreach(@files){
    m/vpi_wrapper_([a-zA-Z_0-9]*).h/;
#    print "Root: $1\n";
    push @funcs, $1;
}

print OFH "#include <stddef.h>\n";

foreach $func (@funcs) {
    print OFH "#include \"vpi_wrapper_$func.h\"\n";
}
print OFH "\n";

print OFH "void (*vlog_startup_routines[])() = {\n";
foreach $func (@funcs) { 
    print OFH "\t${func}_vpi_register,\n";
}
printf OFH "\t0u\n";
print OFH "};\n";

foreach $func (@funcs) {
    print OFH "#include \"vpi_wrapper_$func.c\"\n";
}
