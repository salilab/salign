#!/usr/bin/perl -w

# Declare package name
package salign::CGI_Utils;
# Inherit from Exporter class
use Exporter;
our @ISA = ("Exporter");
our @EXPORT = qw( end_enspec filen_fix filen_fix_jr check_dir_size create_jobn );
# Set version name
our $VERSION = "1.00";
use strict;
use File::Find;
use Fcntl qw( :DEFAULT :flock);
#use salign::CGI_Error; #070702

# Sub for error check during development / Stolen from U.P.
sub end_enspec 
{
 my @message=@_;
 my $q = new CGI;

 my $firstcolor = "#DDDDDD";
 my ($columns,$errortable);

 print $q->header,$q->start_html({-title=>"EnSpec Error Page"});
 $errortable=$q->table({-border=>0, -width=>"95%", -bgcolor=>$firstcolor, -align=>"center"},
             $q->Tr({-cellspacing=>0, -cellpadding=>0},
             $q->td({-align=>"left"},$q->b("EnSpec Error"))),
             $q->Tr({-cellspacing=>0, -cellpadding=>0},
             $q->td({ -align=>"left"},$q->b("An error occured during your request:"))),
             $q->Tr({-cellspacing=>0, -cellpadding=>0},
             $q->td({-align=>"left"},$q->br,$q->b(join($q->br,@message)),$q->br)),
             $q->Tr({-cellspacing=>0, -cellpadding=>0},
             $q->td({-align=>"left"},$q->b("Please click on your browser's \"BACK\" button, and correct the problem.",$q->br))));

 print $errortable;
 print $q->end_html;
 exit;
}
  
# strip uploaded file name and check for dangerous characters
# INPUT: CGI query, uploaded file name
sub filen_fix
{
#  use Salign::CGI_Error; commented 070702
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
     error ($q,$message);
  }
  # Untaint file name if safe
  $filen = $1;
  return ($filen);
}  

# check filename for dangerous characters and convert whitespaces to _
# INPUT: CGI query, file name
sub filen_fix_jr
{
#  use Salign::CGI_Error; commented 070702
  my $q = shift;
  my $filen = shift;
  $filen =~ tr/ /_/;
  # Check filename for dangerous characters
  unless ( $filen =~ /^([\w.-]+)$/ )
  {
     my $message = "Invalid file name: \n";
     $message .= "File name may contain letters, numbers, underscores, ";
     $message .= "spaces, periods and hyphens \n";
     error ($q,$message);
  }
  # Untaint file name if safe
  $filen = $1;
  return ($filen);
}  

# create a job name and block it for others
# INPUT: $q, path to job name block files, no of times to search for free name
sub create_jobn
{
#  use Salign::CGI_Error; commented 070702
  my $q = shift;
  my $block_dir = shift;
  my $max_open_tries = shift;

  # create random integer between 1 and 1000
  my $rand_n = int(rand 1000) + 1;
  my $time = time();
  my $open_tries = 0;

  # open block file named $time_SA_$rand_n.blk
  # making sure that it does not exist
  until (sysopen(BLOCK, "$block_dir/$time" . "_SA_" . "$rand_n.blk", O_WRONLY | O_CREAT | O_EXCL))
  {
     $rand_n = int(rand 1000) + 1;
     $open_tries++;
     if ($open_tries >= $max_open_tries)
     {
        error($q,"Unique job name not found ");
     }
  }
  close BLOCK;

  # create job name $time_SA_$rand_n
  my $job_name = $time . "_SA_" . $rand_n;
  chmod(oct(666),"$block_dir/$job_name.blk") or die "Can't change block file mode: $!\n";
  return($job_name);
}

# calculate the total size of a directory, including the current upload files
# If the calculated size is larger than $max_dir_size error is called.
# INPUT: $q, directory to check, maximum directory size
sub check_dir_size
{
#  use Salign::CGI_Error; commented 070702
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
     error($q, "Write directory full");
  }
}

# Return true when evaluated
1;

