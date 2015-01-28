#!/usr/bin/perl

use strict;

###############################################################################
# File:    icreader.pl
# Author:  Federico Thiella <fthiella@gmail.com>
# Date:    January 2015
# Version: Alpha 0.1
###############################################################################
#
# read iCobol .XD data files, using the same .XDT specs used for ODBC,
# and print columns as CSV values
# 
###############################################################################

use Config::INI::Reader;

# ###
# international settings
# ###
my $separator = ';';
my $precision = '.';
my $quote = '"';

# ###
# read parameters (XD file, XDT specs, buff len)
# I still don't know how to get the total length of a single record from the .XD file, so we have to
# read it from the command line, it's often 20 or 24 or 16... but it can be anything, depending on the number of keys
# ###

my ($filenameXD, $filenameXDT, $buff_len) = @ARGV;

my $header;
my $row;

# ###
# read the metadata from the XDT file
# the INI reader library fails to read the Columns section, we have to add a = after each column name,
# don't know if it's a bug of the library or if it is the ODBC Columns section that is not not standard
# also INI files on the Windows platform are case insensitive, while the hash implementation is case sensitive,
# and to make things worse, hashes have no order... maybe I should switch to another library
# ##
my $meta = Config::INI::Reader->read_file($filenameXDT);
my $Table = $meta->{Table};
my $Columns = $meta->{Columns};
my $MaxRecordSize = $Table->{MaxRecordSize}; # just trust the contents of the XDT file. Still don't know how to get it from the binary

print join $separator, sort keys $Columns;
print "\n";

open(XD, '<', $filenameXD) or die $!;
binmode(XD);

# ###
# read header, it looks like it's always 2Kb, most of the header is just empty,
# still don't know what's inside
# ###
read (XD, $header, 512);
if ($header =~ /^\x01\x05/) {
  print STDERR "header=2048\n";
  read (XD, $header, 2048-512);
} else { print STDERR "header=512\n"; }

# ###
# read each row in sequence
# ###
while ( (read (XD, $row, $MaxRecordSize + $buff_len)) != 0 ) {
  # ###
  # read status, still unsure about the meaning
  # ###
  my $status1 = substr $row, 1, 1; # \x00 = void row, \x01 = valid row, \x81 = deleted row, other values?

  if ( $status1 =~ /^\x01$/ ) {
	my @vals = ();
	
	for my $key (sort keys $Columns) {
	    my $col = $meta->{$key};
	    
	    for ($col->{Type}) {
	      if (/ALPHANUMERIC/i) {
		if (substr($row, ($buff_len-1)+$col->{Position}, $col->{Length}) =~ /\S/) {
		  # if the string contains at least one significant character, add it quoted
		  # not too common in COBOL, but we should escape quotes!
		  my $field = substr($row, ($buff_len-1)+$col->{Position}, $col->{Length});
		  if (($field =~ /^[\w\s\*\,\.\/]+$/) or (1==1)) { # some fields contain garbage, just print N/P in such case
		    $field =~ s/\s+$//; # trim left spaces
		    push @vals, $quote.$field.$quote;  
		  } else {
		    push @vals, "N/P";
		  }
		} else {
		  # otherwise, consider it null
		  push @vals, '';
		}
	      }
	      elsif (/DISPLAY/i) {
		push @vals, substr($row, ($buff_len-1)+$col->{Position}, $col->{Precision}).(($col->{Scale} eq "0")?(''):($precision.substr($row, ($buff_len-1)+$col->{Position}+$col->{Precision}, $col->{Scale})));
	      }
	      elsif (/UNSIGNED COMP/i) { # ignoring scale at the moment
		if ($col->{Length} == 1) {
		  push @vals, unpack('C', substr($row, ($buff_len-1)+$col->{Position}, 1)); 
		} elsif ($col->{Length} == 2) {
		  push @vals, unpack('n', substr($row, ($buff_len-1)+$col->{Position}, 2));
	        } elsif ($col->{Length} == 3) {
		  push @vals, unpack('C', substr($row, ($buff_len-1)+$col->{Position}, 1))*256*256 + unpack('C', substr($row, ($buff_len-1)+$col->{Position}+1, 1))*256 + unpack('C', substr($row, ($buff_len-1)+$col->{Position}+2, 1));
	        } else {
		  push @vals, 'N/C';
	        }
	      }
	      elsif (/COMP DATE GROUP/i) {
		my $date;

		if (($col->{Length} == 6)||(($col->{Length} == 4))) {
		  $date = unpack('n', substr($row, ($buff_len-1)+$col->{Position}, 2)).'-'.unpack('C', substr($row, ($buff_len-1)+$col->{Position}+2, 1)).'-'.unpack('C', substr($row, ($buff_len-1)+$col->{Position}+3, 1))
		} else {
		  $date = 'D/E';
		}

		push @vals, $date;
	      }
	      else {
		push @vals, 'N/D';
	      }
	    }
	}
	
	print join $separator, @vals; print "\n";
  }
}  

close(XD);
