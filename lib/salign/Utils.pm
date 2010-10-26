#!/usr/bin/perl -w

# Declare package name
package salign::Utils;
# Inherit from Exporter class
use Exporter;
our @ISA = ("Exporter");
our @EXPORT = qw( read_conf notify_by_mail log_message ascii_chk dir_chk );
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

# Send email
# INPUT: recipient e-mail address, subject and body message
sub notify_by_mail
{
  my $email = shift;
  my $subject = shift;
  my $message = shift;
   
  open SENDMAIL, "|/usr/lib/sendmail -oi -t -F 'SALIGN Server Admin' -f 'salign\@salilab.org'" or print "Can't open sendmail: $!\n";
  print SENDMAIL "To: $email\n";
  print SENDMAIL "Subject: $subject\n";
  print SENDMAIL "$message\n";

  close SENDMAIL or print "Sendmail didn't close nicely\n";
}

# Add a message to log file specified by caller
# INPUT: path to directory containing log file, name of log file, message to be logged
sub log_message
{
  my $log_dir = shift;
  my $log_file = shift;
  my $message = shift;

  my $time = localtime();
  unless ( -d $log_dir ) { system ("mkdir -p $log_dir") }
  open LOG, ">> $log_dir/$log_file" or print "Can't open $log_file: $!\n";
  print LOG $$, ":", $time, ":", $message, "\n";
  close LOG;
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

# Return true when evaluated
1;

