#!/usr/bin/perl

###############################################################################
# File:    icreader.pl
# Author:  Federico Thiella <fthiella@gmail.com>
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
use Text::CSV;

our $VERSION     = "0.13";
our $RELEASEDATE = "January 06th, 2017";

sub max ($$) { $_[ $_[0] < $_[1] ] }
sub min ($$) { $_[ $_[0] > $_[1] ] }

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

sub get_alphanumeric {
    my ($args) = @_;

    my $field = $args->{data};

    if ( $field =~ /\S/ ) {
        if ( ( $field =~ /[^[:print:]]+/ ) && ( $field !~ /\x00/ ) )
        {    # some fields contain garbage, just print N/P in such case

            $field =~ s/\s+$//;    # trim left spaces
            $field =~ s/\x00//g;
            $field =~ s/\n//g;
            $field =~ s/\a//g;
            return $field;

        }
        else {

            $field =~ s/\s+$//;    # trim left spaces
                                   # only keep printable characters
            $field =~ s/[^[:print:]]+//g;

            # remove chr(0)
            $field =~ s/\x00//g;
            $field =~ s/\n//g;
            $field =~ s/\a//g;
            return $field;

        }
    }

    return '';
}

sub get_display {

    # display and unsigned display at the moment are the same
    my ($args) = @_;

    my $d = substr( $args->{data}, 0, $args->{precision} )
      . (
          ( $args->{scale} eq "0" )
        ? ('')
        : ( $args->{decimal_separator}
              . substr( $args->{data}, $args->{precision}, $args->{scale} ) )
      );
    $d =~ s/\x00//g;
    return $d;
}

sub get_unsigned_display {
    my ($args) = @_;

    my $d = substr( $args->{data}, 0, $args->{precision} )
      . (
          ( $args->{scale} eq "0" )
        ? ('')
        : ( $args->{decimal_separator}
              . substr( $args->{data}, $args->{precision}, $args->{scale} ) )
      );
    $d =~ s/\x00//g;
    return $d;
}

sub get_unsigned_comp {

    # ignoring scale at the moment
    my ($args) = @_;

    if ( $args->{length} == 1 ) {
        return unpack( 'C', substr( $args->{data}, 0, 1 ) );
    }
    elsif ( $args->{length} == 2 ) {
        return unpack( 'n', substr( $args->{data}, 0, 2 ) );
    }
    elsif ( $args->{length} == 3 ) {
        return
          unpack( 'C', substr( $args->{data}, 0, 1 ) ) * 256 * 256 +
          unpack( 'C', substr( $args->{data}, 1, 1 ) ) * 256 +
          unpack( 'C', substr( $args->{data}, 2, 1 ) );
    }
    return 'N/C';
}

sub get_comp_date_group {
    my ($args) = @_;

    if ( ( $args->{length} == 6 ) || ( $args->{length} == 4 ) ) {
        return
            unpack( 'n', substr( $args->{data}, 0, 2 ) ) . '-'
          . unpack( 'C', substr( $args->{data}, 2, 1 ) ) . '-'
          . unpack( 'C', substr( $args->{data}, 3, 1 ) );
    }

    return 'D/E';
}

sub get_field {
    my ($args) = @_;

    my %f = (
        'alphanumeric'     => \&get_alphanumeric,
        'display'          => \&get_display,
        'unsigned display' => \&get_unsigned_display,
        'unsigned comp'    => \&get_unsigned_comp,
        'comp date group'  => \&get_date_group
    );

    if ( defined $f{ lc $args->{type} } ) {
        return $f{ lc $args->{type} }( $args->{args} );
    }
    return ( lc $args->{type} ) . ' N/D';
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
    'xd=s'  => \$filenameXD,
    'xdt=s' => \$filenameXDT,
    'b=i'   => \$buff_len,
    's=s'   => \$separator,
    'p=i'   => \$precision,
    'q=s'   => \$quote,
    'v'     => \$version,
    'h'     => \$help,
);

if ($help) {
    do_help;
    exit;
}

if ($version) {
    do_version;
    exit;
}

die "Please specfy XD source archive, XDT record layout, and buffer length\n"
  unless ( ($filenameXD) && ($filenameXDT) && ($buff_len) );

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
my $meta          = Config::INI::Reader->read_file($filenameXDT);
my $Table         = $meta->{Table};
my $Columns       = $meta->{Columns};
my $MaxRecordSize = $Table->{MaxRecordSize};    # just trust the contents of the XDT file...

my $csv = Text::CSV->new(
    {
        binary     => 1,
        quote_char => $quote,
        sep_char   => $separator
    }
  )                           # should set binary attribute.
  or die "Cannot use CSV: " . Text::CSV->error_diag();

# my $buff_len = 20; I'm not able to calculate it, so we just ask it on the command line.... until I figure out how to get it

my $csvstatus     = $csv->combine( sort keys %{$Columns} );    # combine columns into a string
my $csvline       = $csv->string();                            # get the combined string
print $csvline, "\n";

open( XD, '<', $filenameXD ) or die $!;
binmode(XD);

# ###
# read header, it looks like it's always 2Kb, most of the header is just empty,
# still don't know what's inside
# ###
read( XD, $header, 512 );
if ( $header =~ /^\x01\x05/ ) {
    print STDERR "header=2048\n";
    read( XD, $header, 2048 - 512 );
}
else {
    print STDERR "header=512\n";
}

# ###
# read each row in sequence
# ###
while ( ( read( XD, $row, $MaxRecordSize + $buff_len ) ) != 0 ) {

    # ###
    # read status, still unsure about the meaning
    # ###
    my $status1 = substr $row, 1, 2;

    if ( $status1 =~ /^(\x01.*|\x10.*|\x11.*|\x12.*|\x20.*|\x01.*|\x02.*|\x10.*|\x21.*|\x22.*|\x00[^\x00])$/ )
    {
        my @vals = ();

        # loop throug all columns (ordered by asc column name, not the order provided in the xdt file)
        for my $key ( sort keys %{$Columns} ) {
            my $col = $meta->{$key};

            push @vals,
              get_field(
                {
                    type => $col->{Type},
                    args => {
                        data => substr(
                            $row,
                            ( $buff_len - 1 ) + $col->{Position},
                            max( $col->{Length}, $col->{Precision} // 0 )
                        ),
                        length            => $col->{Length},
                        precision         => $col->{Precision},
                        scale             => $col->{Scale},
                        decimal_separator => $precision
                    }
                }
              );
        }

        $csvstatus = $csv->combine(@vals);    # combine columns into a string
        $csvline   = $csv->string();          # get the combined string
        print $csvline, "\n";
    }
}

close(XD);
