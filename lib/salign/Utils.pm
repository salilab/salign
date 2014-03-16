package salign::Utils;
# Inherit from Exporter class
use Exporter;
our @ISA = ("Exporter");
our @EXPORT = qw( read_conf ascii_chk dir_chk );
# Set version name
our $VERSION = "1.00";
use strict;
use File::Find;
use Fcntl qw( :DEFAULT :flock);

# Read config file and return as a hash
# INPUT: Path to conf file
sub read_conf
{ 
  my $conf_ref;
  my $conf_file = shift;
  open CONF, "<$conf_file" or die "Can't open conf file: $!";
  while (<CONF>) 
  {
      chomp;                  # no newline
      s/#.*//;                # no comments
      s/^\s+//;               # no leading white
      s/\s+$//;               # no trailing white
      next unless length;     # anything left?
      my ($key, $value) = split(/\s*=\s*/, $_, 2);
      $conf_ref->{$key} = $value;
  }
  close CONF;
  return($conf_ref);
}

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

# Check if a file is a directory
# INPUT: path to directory of file, file name
sub dir_chk
{
  my $path = shift;
  my $filen = shift;
#  my $q = shift;
  my $cmd = "file $path/$filen";
  my $direc = 0;

  open ( FILE, "$cmd |" );
  while ( my $line = <FILE> )
  {
     if ( $line =~ /directory/i )
     {
        $direc = 1;
     }
  }
  close FILE;
  return($direc);
}

1;

