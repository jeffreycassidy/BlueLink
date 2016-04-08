#!/usr/bin/perl
#
# Converts a .enum text file into a BSV enum definition in its own .bsv file
#
# make_bsv_enum.pl <fnroot> <inputdir> <outputdir>
#
# <Verilog base>
#   <enum_name_0>
#   <enum_value_0>
#   <enum_comment_0>
#
# The Verilog base is the base prefix (eg. 13'h) to apply to the constant; necessary to get the right bit width and interpretation
#
# For each subsequent triplet of lines, it will define an enum entry with the given name and value, along with a comment
#
# The script uses deriving(Bits,Eq,FShow) so that the enum name can be displayed.
#
# NOTE: The last value given is the default in the event that unpacking fails; it should be defined appropriately to avoid errors
# (ie. it should be a value interpreted as invalid)
#
# Also creates a C/C++ .h file with an enum

$/ = undef;

if ($#ARGV != 2)
{
    print "Incorrect number of arguments\n";
    print "Usage: make_bsv_enum.pl <fnroot> <inputdir> <outputdir>\n";
    print "  Loads from <fnroot>.enum and writes to <outputroot>.bsv and .h\n";
    print "  NOTE: BSV will take the last value to be the default if unpacking fails, so a default value should be last\n";
    exit -1;
}

my $root = $ARGV[0];
my $inputdir = $ARGV[1];
my $outputdir = $ARGV[2];

open IFH,"<${inputdir}/${root}s.enum" or die "Failed to open ${inputdir}/${root}s.enum for reading";

open OFH,">${outputdir}/${root}s.bsv";

open OFHC, ">${outputdir}/${root}s.h";

my @lines = split(/\n/,<IFH>);

print OFH  "// DO NOT EDIT! Automatically generated file\n";
print OFH  "// Created by make_bsv_enum.pl from ${inputdir}/${root}.enum\n";
print OFH  "//   Original enum file derived from IBM technical specifications (c) IBM, 2014\n\n";
print OFH  "package ${root}s;\n\n";
print OFH  "import FShow::*;\n";
print OFH  "typedef enum {\n";
my @values;
my $i=0;

my ($literalpfx, @lines) = @lines;

$literalpfx =~ m/([0-9]*)'([hb])/ || die "Unrecognized type specifier \"$literalpfx\": expecting NN'(h|b) for hex or binary";
my $bits=$1;
my $radix=$2;

my $c_type="UNKNOWN_TYPE";

if ($bits < 8){
    $c_type = "uint8_t"; }
elsif ($bits < 16){
    $c_type = "uint16_t"; }
elsif ($bits < 32){
    $c_type = "uint32_t"; }
elsif ($bits < 64){
    $c_type = "uint64_t"; }
else
    { die "Invalid bit size (>64): $bits"; }

print OFHC "// DO NOT EDIT! Automatically generated file\n";
print OFHC  "// Created by make_bsv_enum.pl from PSL${root}s.enum\n";
print OFHC  "//   Original enum file derived from IBM technical specifications (c) IBM, 2014\n\n";

print OFHC "#include <string>\n#include <boost/bimap.hpp>\n\n";

print OFHC "\n\nclass PSL${root}s {\n";
print OFHC "public:\n";
print OFHC "\tenum enumvalue : $c_type {\n";

print "radix $radix, bits $bits\n";

my %enumvals;


while(@lines >= 3)
{
	if ($lines[0] =~ /^(0x)?[0-9A-Fa-f]+$/)
	{ ($cmdcode,$cmdname,$comment,@lines)=@lines; }
	else
	{ ($cmdname,$cmdcode,$comment,@lines)=@lines; }
    $cmdcode =~ s/0x//;
    $cmdname=ucfirst(lc($cmdname));
	
	$values[$i]=$cmdname;
	$i=$i+1;

    $delim = @lines>0 ? "," : " ";

    printf OFH "\t%-30s","$cmdname=$literalpfx$cmdcode$delim";
    print OFH  "\/\/ $comment\n";

    my $c_base = $radix eq "b" ? "0b" : "0x";

    $enumvals{$cmdname} = $cmdcode;

    printf OFHC "\t\t%-30s \/\/ $comment\n","$cmdname=$c_base$cmdcode$delim";
}
printf OFHC "\t};\n\n";
print OFHC "private:\n";
print OFHC "\tenumvalue val_;\n";
print OFHC "\tstatic const boost::bimap<enumvalue,std::string> val_str_;\n";
print OFHC "};\n";

print OFHC "\n\n";
print OFHC "boost::bimap<PSL${root}s::enumvalue,std::string> PSL${root}s::val_str_{\n";

my $first=1;
foreach my $enumval (keys %enumvals){
    if ($first==0)
    {
        print OFHC ",\n";
    }
    print OFHC "\tstd::make_pair($enumval,\"$enumval\")";
    $first=0;
}
print OFHC "\n};";

print OFH "} $root deriving(Bits,Eq,FShow);\nendpackage\n";
print OFH "\n//NOTE: The last entry is the default value; it will be chosen if bit unpacking fails\n";

