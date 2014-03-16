package salign::CGI_Utils;
# Inherit from Exporter class
use Exporter;
our @ISA = ("Exporter");
our @EXPORT = qw( filen_fix filen_fix_jr check_dir_size );
# Set version name
our $VERSION = "1.00";
use strict;
use File::Find;

# strip uploaded file name and check for dangerous characters
# INPUT: CGI query, uploaded file name
sub filen_fix
{
  my $q = shift;
  my $long_name = shift;
  my @filename = split (/\/|\\/,$long_name);
  my $filen = pop @filename;
  $filen =~ s/^\s+//;
  $filen =~ s/\s+$//;
  $filen =~ tr/ /_/;
  # Check filename for dangerous characters
  unless ( $filen =~ /^([\w.-]+)$/ )
  {
     my $message = "Invalid file name: \n";
     $message .= "File name may contain letters, numbers, underscores, ";
     $message .= "spaces, periods and hyphens \n";
     die $message;
  }
  # Untaint file name if safe
  $filen = $1;
  return ($filen);
}  

# check filename for dangerous characters and convert whitespaces to _
# INPUT: CGI query, file name
sub filen_fix_jr
{
  my $q = shift;
  my $filen = shift;
  $filen =~ tr/ /_/;
  # Check filename for dangerous characters
  unless ( $filen =~ /^([\w.-]+)$/ )
  {
     my $message = "Invalid file name: \n";
     $message .= "File name may contain letters, numbers, underscores, ";
     $message .= "spaces, periods and hyphens \n";
     die $message;
  }
  # Untaint file name if safe
  $filen = $1;
  return ($filen);
}  

# calculate the total size of a directory, including the current upload files
# If the calculated size is larger than $max_dir_size error is called.
# INPUT: $q, directory to check, maximum directory size
sub check_dir_size
{
  my $q = shift;
  my $input_dir = shift;
  my $max_dir_size = shift;
  my $present_size = 0;
  # Calculate present size of directory in Bytes, including sub directories
  my %options;
  $options{'wanted'} = sub { $present_size += -s; };
  $options{'untaint'} = 1;
  find (\%options, $input_dir);

  # Check that the directory will not be too large after the uploads
  if ($present_size + $ENV{CONTENT_LENGTH} > $max_dir_size)
  {
     die "Write directory full";
  }
}

1;

