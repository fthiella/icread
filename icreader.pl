#!/usr/bin/perl

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

=pod
    Copyright 2015, Federico Thiella (fthiella@gmail.com)
Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
   limitations under the License.
=cut

use strict;
use warnings;

use Config::INI::Reader;
use Getopt::Long;

our $VERSION = "0.11";
our $RELEASEDATE = "July 25st, 2016";

sub do_help {
	print <<endhelp;
Usage: icreader.pl [options]
       perl icreader.pl [options]

Options:
  -xd   source XD cobol archive
  -xdt  record layout XDT file
  -b    buffer length
  -s    separator (default ;)
  -p    precision (default .)
  -q    quote (default ")
  -h    help page

Project GitHub page: https://github.com/fthiella/icread
endhelp
}

sub do_version {
	print "./icreader.pl $VERSION ($RELEASEDATE)\n";
}

# get command line options

my $filenameXD;
my $filenameXDT;
my $buff_len;
my $separator;
my $precision;
my $quote;
my $help;
my $version;

GetOptions(
	'xd=s'      => \$filenameXD,
	'xdt=s'     => \$filenameXDT,
	'b=i'       => \$buff_len,
	's=s'       => \$separator,
	'p=i'       => \$precision,
	'q=s'       => \$quote,
	'v'         => \$version,
	'h'         => \$help,
);

if ($help)
{
	do_help;
	exit;
}

if ($version)
{
	do_version;
	exit;
}

die "Please specfy XD source archive, XDT record layout, and buffer length\n" unless (($filenameXD) && ($filenameXDT) && ($buff_len));

# default international settings
unless ($separator) { $separator = ';'; }
unless ($precision) { $precision = '.'; }
unless ($quote)     { $quote     = '"'; }

# read file

my $header;
my $row;

# ###
# read the metadata from the XDT file
# the INI reader library fails to read the Columns section, we have to add a = after each column name,
# don't know if it's a bug of the library or if it is the ODBC Columns section that is not not standard
# also INI files on the Windows platform are case insensitive, while the hash implementation is case sensitive,
# and to make things worse, hashes have no order... maybe I should switch to another library
# ##
my $meta = Config::INI::Reader->read_file($filenameXDT);
my $Table = $meta->{Table};
my $Columns = $meta->{Columns};
my $MaxRecordSize = $Table->{MaxRecordSize}; # just trust the contents of the XDT file...

# my $buff_len = 20; I'm not able to calculate it, so we just ask it on the command line.... until I figure out how to get it

print join $separator, sort keys %{$Columns};
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
  	#print substr($row, 20), "\n";
	
	for my $key (sort keys %{$Columns}) {
	    my $col = $meta->{$key};
	    
	    for ($col->{Type}) {
	      if (/ALPHANUMERIC/i) {
		if (substr($row, ($buff_len-1)+$col->{Position}, $col->{Length}) =~ /\S/) {
		  # if the string contains at least one significant character, add it quoted
		  # not too common in COBOL, but we should escape quotes!
		  my $field = substr($row, ($buff_len-1)+$col->{Position}, $col->{Length});
		  if (($field =~ /[^[:print:]]+/) && ($field !~ /\x00/)) { # some fields contain garbage, just print N/P in such case
		    $field =~ s/\s+$//; # trim left spaces
		    push @vals, $quote.$field.$quote;  
		  } else {
                    # only keep printable characters 
                    $field =~ s/[^[:print:]]+//g;
                    # remove chr(0)
                    $field =~ s/\x00//g;
		    push @vals, $field;
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
	
	print join $separator, @vals;
	print "\n";
  }
}  

close(XD);
