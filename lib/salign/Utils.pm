package salign::Utils;
# Inherit from Exporter class
use Exporter;
our @ISA = ("Exporter");
our @EXPORT = qw( ascii_chk );
# Set version name
our $VERSION = "1.00";
use strict;
use File::Find;
use Fcntl qw( :DEFAULT :flock);

# Check that a file is an ascii file
# INPUT: path to directory of file, file name
sub ascii_chk
{
  my $dir = shift;
  my $filen = shift;
#  my $q = shift;
  my $cmd = "file $dir/$filen";
  my $ascii = 0;

  open ( FILE, "$cmd |" );
  while ( my $line = <FILE> )
  {
     if (( $line =~ /\sascii\s/i ) || ( $line =~ /\stext\s/i ))
     {
        $ascii = 1;
     }
  }
  close FILE;
  return($ascii);
}

1;
