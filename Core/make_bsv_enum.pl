#!/usr/bin/perl
#
# Converts a .enum text file into a BSV enum definition in its own .bsv file
#
# make_bsv_enum.pl <fnroot>
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

$/ = undef;

if ($#ARGV != 0)
{
    print "Incorrect number of arguments\n";
    print "Usage: make_bsv_enum.pl <fnroot>\n";
    print "  Loads from PSL<fnroot>s.enum and writes to PSL<fnroot>s.bsv\n";
    print "  NOTE: BSV will take the last value to be the default if unpacking fails, so a default value should be last\n";
    exit -1;
}

my $root = $ARGV[0];

open IFH,"<PSL${root}s.enum";

open OFH,">PSL${root}s.bsv";

my @lines = split(/\n/,<IFH>);

print OFH  "// DO NOT EDIT! Automatically generated file\n";
print OFH  "// Created by make_bsv_enum.pl from PSL${root}s.enum\n";
print OFH  "//   Original enum file derived from IBM technical specifications (c) IBM, 2014\n\n";
print OFH  "package PSL${root}s;\n\n";
print OFH  "import FShow::*;\n";
print OFH  "typedef enum {\n";

my @values;
my $i=0;

my ($literalpfx, @lines) = @lines;

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
}

print OFH "} PSL$root deriving(Bits,Eq,FShow);\nendpackage\n";
print OFH "\n//NOTE: The last entry is the default value; it will be chosen if bit unpacking fails\n";
