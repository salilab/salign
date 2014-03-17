package salign::index_page;

# where you give error at present but dont want it, you could instead go back 
# to the previous page with a message. when not error the message would simply 
# be "".

use strict;
use File::Find;
use Cwd;
use Fcntl qw( :DEFAULT :flock);
use DB_File;
use salign::CGI_Utils;
use salign::Utils;
use salign::constants;
use saliweb::frontend qw(pdb_code_exists);
use File::Copy;
use Archive::Tar;

# ======================= SUB ROUTINES ========================
sub main
{
  my ($self, $q) = @_;

  my $job_name = $q->param('job_name');
  my $cur_state = $q->param('state') || 'home';
  my $upld_pseqs = $q->param('upld_pseqs') || 0;
  my $email = $q->param('email') || "";
  my $pdb_id = $q->param('pdb_id') || "";

  # start requested option
  if ( $cur_state eq "home" ) 
  { 
     return home($self, $q,$job_name,$upld_pseqs,$email,$pdb_id);
  }
  elsif ( $cur_state eq "Upload" )
  {
     return upload_main($self, $q,$job_name,$upld_pseqs,$email,$pdb_id);
  }
  elsif ( $cur_state eq "Continue" )
  {
     return customizer($self, $q,$job_name,$upld_pseqs,$email,$pdb_id);
  }
  elsif ( $cur_state eq "Advanced" )
  {
     my $caller = $q->param('caller');
     if ( $caller eq 'str-str' )
     {
        return adv_stst($self, $q,$job_name,$email);
     }
     elsif ( $caller eq 'str-seq' )
     {
        return adv_stse($self, $q,$job_name,$email);
     }
     elsif ( $caller eq '2s_sese' || $caller eq '1s_sese' )
     {
        return adv_sese($self, $q,$job_name,$email);
     }
     else { die "Caller $caller for advanced view does not exist"; }
  }
  else { die "Routine $cur_state does not exist"; }
}

# Generate front page of salign interface
# Note that reset will only work first time since defaults change
sub home
{
  my $self = shift; 
  my $q = shift; 
  my $job_name = shift;
  my $upld_pseqs = shift;
  my $email = shift;
  my $pdb_id = shift;

  # Get job object (including upload directory)
  my $job;
  if ($job_name) {
    $job = $self->resume_job($job_name);
  }

  # Start html
  my $msg = print_body1a_intro($self, $q)
         .  print_body2_general_information($self, $q, $email)
         .  print_body3_input_alignment($q)
         .  print_body3a_sequence($self, $q)
         .  print_body3b_file($self, $q)
         .  print_body3c_PDB_code($self, $q);

  $msg .=  "<hr />Uploaded files: <br />";

  if (!$job)
  {
     $msg .= $q->p("No files uploaded");
  }
  else
  {
     # fetch the names of all uploaded files
     my $upl_dir = $job->directory . "/upload";
     my @file_names;
     my @file_times;
     my @file_sizes;
     my $ls_cmd = "/bin/ls -l $upl_dir";
     open ( LS, "$ls_cmd |" );
     while ( my $line = <LS> )
     {
        if ( $line =~ /No such file or directory/ )
        {
           die "Job directory non existent";
        }
	elsif ( $line =~ /^d/ || $line =~ /^total/i ) { next; }
	else
	{
           my @file_stats = split (/\s+/,$line);
	   push @file_names,$file_stats[8];
	   push @file_sizes,$file_stats[4];
	   my $time = $file_stats[5] . " " . $file_stats[6] . " " . $file_stats[7];
	   push @file_times,$time;
	}
     }
     close LS;
     
     if ( $#file_names == -1 )
     {
        $msg .= $q->p("No files uploaded");
     }
     else
     {
        foreach my $i ( 0 .. $#file_names )
	{
	   my $nice_size = make_size_nice($file_sizes[$i]);
	   $msg .= $q->p("$file_names[$i],  $nice_size,  $file_times[$i]");
	}
     }
  } 
  if ($upld_pseqs > 0)
  {
     if ($upld_pseqs == 1)
     {
        $msg .= $q->hr.
	      $q->p("$upld_pseqs pasted sequence uploaded");
     }
     else
     {
        $msg .= $q->hr.
	      $q->p("$upld_pseqs pasted sequences uploaded");
     }
  }


  $msg .= "<hr />";

  $msg .= print_body3d_continue($q, $job, $upld_pseqs);
  return $msg;
}	

# Main sub routine for upload option
# customizer creates upl_dir in a different way than upload_main. if you want
# conformity, i suggest to use the customizer method in both places.
sub upload_main
{
  my $self = shift;
  my $q = shift;
  my $job_name = shift;
  my $upld_pseqs = shift;
  my $email = shift;
  my $pdb_id = shift;

  my $job = $self->get_job_object($job_name);
  $job_name = $job->name;

  my $msg = '';

  # Run sub check_dir_size to see that there is space for the request
  check_dir_size($q,$job->directory);
  
  # Check what is being uploaded
  my $upl_file = $q->param('upl_file'); 
  my $paste_seq = $q->param('paste_seq'); 
  if ( $upl_file eq "" && $paste_seq eq "" )
  {
     $msg .= home($self, $q,$job_name,$upld_pseqs,$email,$pdb_id);
  }   
  else
  {
     my $upl_dir = $job->directory . "/upload";
     #save all filenames present in $upl_dir in hash
     my %upldir_files;
     opendir ( UPLOAD, $upl_dir ) or die "Can't open $upl_dir: $!\n";
     while ( defined (my $file = readdir UPLOAD) )
     {
        #skip . and ..
        next if $file =~ /^\.\.?$/;
        #set file name as hash key
        $upldir_files{$file} = 1;
     }
     closedir (UPLOAD);

     # upload file if exists
     if ( $upl_file ne "" )
     {
        my $filen = file_upload($q,$upl_dir,\%upldir_files,$upl_file);
	unless ($filen eq "")
	{
           my $ascii = ascii_chk($upl_dir,$filen);
	   if ($ascii == 1) 
	   { 
	      my $file_type = file_cat($upl_dir,$filen,$q);
	      add_to_DBM($filen,$file_type,$job->directory); 
           }
	   else { unzip($upl_dir,$filen,$q,\%upldir_files,$job->directory); }
        }
     }	
     # save pasted sequence if exists
     if ( $paste_seq ne "" )
     {
        $paste_seq =~ s/[\r\n\s]+//g;
	save_paste($job->directory,$paste_seq,$upld_pseqs);
	$upld_pseqs++;
     }
     $msg .= home($self, $q,$job_name,$upld_pseqs,$email,$pdb_id);
  }
  return $msg;
}


# Upload files if needed, guess what user wants to do
# and display appropriate page.
sub customizer
{
  my $self = shift;
  my $q = shift;
  my $job_name = shift;
  my $upld_pseqs = shift;
  my $email = shift;
  my $pdb_id = shift;
  my $upl_file = $q->param('upl_file'); 
  my $paste_seq = $q->param('paste_seq');

  my $job = $self->get_job_object($job_name);
  $job_name = $job->name;

  my $upl_dir = $job->directory . "/upload";

  my $msg = '';

  # upload file if exists
  if ( $upl_file ne "" )
  {
     check_dir_size($q,$job->directory);
     #save all filenames present in $upl_dir in hash
     my %upldir_files;
     opendir ( UPLOAD, $upl_dir ) or die "Can't open $upl_dir: $!\n";
     while ( defined (my $file = readdir UPLOAD) )
     {
        #skip . and ..
        next if $file =~ /^\.\.?$/;
        #set file name as hash key
        $upldir_files{$file} = 1;
     }
     closedir (UPLOAD);
     my $filen = file_upload($q,$upl_dir,\%upldir_files,$upl_file);
     unless ($filen eq "")
     {
        my $ascii = ascii_chk($upl_dir,$filen);
  	if ($ascii == 1) 
	{ 
	   my $file_type = file_cat($upl_dir,$filen,$q);
	   add_to_DBM($filen,$file_type,$job->directory); 
	}
	else { unzip($upl_dir,$filen,$q,\%upldir_files,$job->directory); }
     }   
  }
  
  # save pasted sequence if exists
  if ( $paste_seq ne "" )
  {
     if ( $upl_file eq "" ) { check_dir_size($q,$job->directory); }
     $paste_seq =~ s/[\r\n\s]+//g;
     save_paste($job->directory,$paste_seq,$upld_pseqs);
     $upld_pseqs++;
  }
  
  # load uploaded files DBM to hash and count instances
  my %upl_files;
  my %upl_count;
  $upl_count{'str'} = 0;
  $upl_count{'ali_st'} = 0;
  $upl_count{'ali_stse'} = 0;
  $upl_count{'ali_seq'} = 0;
  $upl_count{'used_str'} = 0;    # can only be incremented in sub chk_alistrs
  if ( -e $job->directory . "/upl_files.db" )
  {
     #Get uploaded files
     tie my %tie_hash, "DB_File", $job->directory . "/upl_files.db", O_RDONLY 
       or die "Cannot open tie to filetype DBM: $!";
     while ( my ($filen,$type) = each %tie_hash )
     {
        if ( $type eq 'str' )        # structure file
	{
           $upl_files{'str'}{$filen} = 1;
	   $upl_count{'str'}++;
	}
        elsif ( $type =~ /st$/ )     # ali file with only structures
	{
	   my @type_split = split(/-/,$type);
	   $upl_files{'ali_st'}{$filen}{'length'} = $type_split[1];
	   @{ $upl_files{'ali_st'}{$filen}{'st_ents'} } = split(/_/,$type_split[2]);
	   $upl_count{'ali_st'}++;
	} 
	elsif ( $type =~ /stse$/ )     # ali file with structures and seqs
	{
	   my @type_split = split(/-/,$type);
	   $upl_files{'ali_stse'}{$filen}{'length'} = $type_split[1];
	   @{ $upl_files{'ali_stse'}{$filen}{'st_ents'} } = split(/_/,$type_split[2]);
	   $upl_count{'ali_stse'}++;
	} 
	else                         # ali file without structures
	{
	   my @type_split = split(/-/,$type);
	   $upl_files{'ali_seq'}{$filen}{'format'} = $type_split[0];
	   $upl_files{'ali_seq'}{$filen}{'length'} = $type_split[1];
	   $upl_count{'ali_seq'}++;
        }
     }
     untie %tie_hash;
  }

  my %lib_PDBs;
  if ( $pdb_id ne "" )
  {
     #Believe \r should be there but haven't tested this. 
     #If problems, skip it. Works without it. 
#    print $q->p($pdb_id);
     foreach my $tmp_PDB ( split(/\r\n/,$pdb_id) )
     {
          $tmp_PDB =~ s/^\s+//;
	  $tmp_PDB =~ s/\s+$//;
          $lib_PDBs{'man'}{$tmp_PDB} = 1;
     }
  }

  if ( exists $upl_files{'ali_st'} || exists $upl_files{'ali_stse'} )
  {
     # check if structures in ali files exist and change whats needed if not
     my ($upl_files_ref,$upl_count_ref,$lib_PDBs_ref) = 
     chk_alistrs(\%upl_files,\%upl_count,$job->directory,\%lib_PDBs,$upl_dir);
     %upl_files = %$upl_files_ref;
     %upl_count = %$upl_count_ref;
     %lib_PDBs  = %$lib_PDBs_ref;
  } 
  # guess what user wants
  my $choice = guess(\%upl_files,\%lib_PDBs,$upld_pseqs,\%upl_count);

  if ( $choice eq 'str-str' )
  {
     $msg .= str_str($self, $q,$email,\%upl_files,\%lib_PDBs,$job_name);
  }
  elsif ( $choice eq 'str-seq' )
  {
     $msg .= str_seq($self, $q,$email,\%upl_files,\%lib_PDBs,$upld_pseqs,$job_name);
  }
  elsif ( $choice eq '2s_seq-seq' )
  {
     $msg .= twostep_sese($self, $q,$email,\%upl_files,$upld_pseqs,$job_name,\%lib_PDBs);
  }
  elsif ( $choice eq '1s_seq-seq' )
  {
     $msg .= onestep_sese($self,$q,$email,\%upl_files,$upld_pseqs,$job_name);
  }
  return $msg;
}

	
# upload files
sub file_upload
{
  my $q = shift;
  my $upl_dir = shift;
  my $upldir_files = shift;
  my $upl_file = shift;
  my %xupldir_files = %$upldir_files;

  # Extract and security check file name
  my $filen = filen_fix( $q,$upl_file );

  #skip if file with same name exists already
  if ( exists $xupldir_files{$filen} ) { return(""); }
     
  # Get a file handle for the file to upload
  my $fh = $q->upload('upl_file') or die "Can't upload $filen: $!";
  my $buffer = "";

  open(UPLOAD_OUT, ">$upl_dir/$filen") or die "Cannot open $filen: $!";

  # Write contents of upload file to $filen
  while( read($fh,$buffer,BUFFER_SIZE) ) {print UPLOAD_OUT "$buffer";}

  close UPLOAD_OUT;
  return($filen);
}
					  
# Save pasted sequence as a PIR file
sub save_paste
{
  my $job_dir = shift;
  my $seq = shift;
  my $upld_pseqs = shift;
  my $filen = "pasted_seqs.pir";
  my $seq_no = $upld_pseqs + 1;
  my $new;
  if ( -e "$job_dir/$filen" ) { $new = 0; }
  else                        { $new = 1; }
  
  open(PIR_FILE, ">>$job_dir/$filen") or die "Cannot open $filen: $!";
#  print PIR_FILE ">P1;PASTED_SEQ_$seq_no\n";
  print PIR_FILE ">P1;PASTE_$seq_no\n";
  print PIR_FILE "SALIGN pasted seq $seq_no:seq: :: :::::\n";
  print PIR_FILE "$seq*\n\n";
  close PIR_FILE;
}  
  

# check and unzip zip or gzip file.
sub unzip
{
  my $upl_dir = shift;
  my $cmp_file = shift;
  my $q = shift;
  my $upldir_files = shift;
  my $job_dir = shift;
  my %xupldir_files = %$upldir_files;
  my $run_dir = cwd;
  # untaint run directory
  if ($run_dir =~ /(.+)/) {$run_dir = $1;}
  else {die "Can't untaint run directory";}
  my $unzip_dir = $upl_dir . "/unzip";
  
  #check file type
  my $file_cmd = "file $upl_dir/$cmp_file";
  my $type = "unk";
  open ( FILE, "$file_cmd |" );
  while ( my $line = <FILE> )
  {
     if ( $line =~ /\sgzip\s/i )
     {
        $type = "gzip";
     }
     elsif ( $line =~ /\szip\s/i )
     {
        $type = "zip";
     }
  }
  close FILE;

#  die "$upl_dir/$cmp_file $type";

  # if incorrect file format
  if ( $type eq "unk" )  
  {     
     die "Uploaded file $cmp_file not supported file type";
  }

  # create directory for unzipping if it doesn't exist
  unless ( -d $unzip_dir )
  {
     mkdir $unzip_dir or die "Can't create sub directory $unzip_dir: $!\n";
  }
  chdir "$unzip_dir" or die "Can't change working directory to $unzip_dir: $!\n";
#  system ("mv","$upl_dir/$cmp_file","$unzip_dir/$cmp_file");
  move ("$upl_dir/$cmp_file","$unzip_dir/$cmp_file")
    or die "move failed: $cmp_file $!";
  
  # unzip if zip file
  if ( $type eq "zip" )
  {
     system ("unzip","$unzip_dir/$cmp_file");
     # delete zip file post extraction
     unlink ("$unzip_dir/$cmp_file") or die "Couldn't unlink $cmp_file: $!\n";
  }
  # gunzip and untar if .tar.gz file
  else
  {
     my $gunz_file;
     if ($cmp_file =~ /\.gz$/)
     {
        $gunz_file = $cmp_file;
        $gunz_file =~ s/\.gz$//;
     }
     else 
     {   
        $gunz_file = $cmp_file;
	my $cmp_file = $cmp_file . ".gz";
        rename ("$unzip_dir/$gunz_file","$unzip_dir/$cmp_file")
          or die "Couldn't rename $gunz_file: $!\n";
     }	  
     # gunzip  
     system ("gunzip","$unzip_dir/$cmp_file");
     # check that gzipped file really is a tar file
     $file_cmd = "file $unzip_dir/$gunz_file";
     my $tar_file = 0;
     open ( FILE, "$file_cmd |" );
     while ( my $line = <FILE> )
     {
        if ( $line =~ /\star\s/i )
	{
           $tar_file = 1;
	}
     }
     close FILE;
     unless ( $tar_file == 1 )
     {
        throw saliweb::frontend::InputValidationError(
                          "gzip file content not a .tar file");
     }
#     system ("tar", "xf", "$unzip_dir/$gunz_file");
     my $tar = Archive::Tar->new;
     $tar->read("$unzip_dir/$gunz_file",1,{extract=>'true'});
     # delete tar file
     unlink ("$unzip_dir/$gunz_file") or die "Couldn't unlink $gunz_file: $!\n";
  }

  # process all unzipped files
  my @redundant;
  my %unz_files;
  opendir ( UNZIP, $unzip_dir ) or die "Can't open $unzip_dir: $!\n";
  while ( defined (my $file = readdir UNZIP) )
  {
     #skip . and ..
     next if $file =~ /^\.\.?$/;
     $unz_files{$file} = 1;
  }
  closedir (UNZIP);
  foreach my $old_filen ( keys %unz_files )
  {
     my $filen = filen_fix_jr( $q,$old_filen );
     if ( $old_filen ne $filen )  #do stuff if filen has been changed
     {
        #skip file if one with the new name already exists
        if ( exists $unz_files{$filen} ) 
	{
	   push @redundant,$old_filen;
	   next;
        }
	#rename file else (if 2 files have been renamed to the same,
	#the first will simply be overwritten)
	else
	{
           rename ("$unzip_dir/$old_filen","$unzip_dir/$filen")
             or die "Couldn't rename $old_filen: $!\n";
	}
     }
     #check if file is directory. skip if so. (OS X zip file artifact)
     if (-d "$unzip_dir/$filen")
     {
        my $rdstat = rmdir("$unzip_dir/$filen");
#          or die "Could not remove directory in zip file: $!";
        if ($rdstat == 1) { next; } #empty dir, possibly os x zip artifact
        else #remove files and directory, and give error
        {
             if ($filen =~ /^([\w.-]+)$/) {$filen = $1;}
             else {die "Can't untaint directory name";}
             my $bad_dir = "$unzip_dir/$filen";
             opendir(BADDIR, $bad_dir) or die "Can't open $bad_dir: $!";
             while( defined (my $delfil = readdir BADDIR) ) 
             {
                  next if $delfil =~ /^\.\.?$/;     # skip . and ..
                  if ($delfil =~ /^([\w.-]+)$/) {$delfil = $1;}
                  else {die "Can't untaint filename";}
                  unlink ("$bad_dir/$delfil") or die "Couldn't unlink $delfil: $!\n";
             }            
             closedir(BADDIR);
             rmdir($bad_dir);
             throw saliweb::frontend::InputValidationError("You uploaded an archive of a folder containing files. Archives (.zip and .tar.gz) should contain all files in the top level, and not within a folder. Thus, when preparing these, make sure to archive all desired files directly, not a folder containing the files. Please reload SALIGN webserver and follow these instructions."); 
        }
     }
     #check that file is ascii
     my $ascii = ascii_chk($unzip_dir,$filen);
     unless ($ascii == 1) 
     {
        throw saliweb::frontend::InputValidationError(
            "Non ascii file found where only ascii files allowed: $filen");
     }	
     #skip if file with same name exists in $upl_dir
     if ( exists $xupldir_files{$filen} ) 
     { 
        push @redundant,$filen;
	next; 
     }
#     system ("mv","$unzip_dir/$filen","$upl_dir/$filen");
     move ("$unzip_dir/$filen","$upl_dir/$filen")
       or die "move failed: $filen $!";
     my $file_type = file_cat($upl_dir,$filen,$q);
     add_to_DBM($filen,$file_type,$job_dir);
  }
  # delete duplicate file uploads
  foreach my $i ( 0 .. $#redundant )
  {
     unlink ("$unzip_dir/$redundant[$i]") or die "Couldn't unlink $redundant[$i]: $!\n";
  } 
  chdir "$run_dir" or die "Can't change working directory to $run_dir: $!\n";
}


# add filename and filetype to dbm hash
sub add_to_DBM
{
  my $filen = shift;
  my $file_type = shift;
  my $job_dir = shift;
  
  my $pre_made = 0;
  if ( -e "$job_dir/upl_files.db") { $pre_made = 1; }
  
  tie my %file_types, "DB_File", "$job_dir/upl_files.db" , O_WRONLY | O_CREAT
    or die "Cannot open tie to filetype DBM: $!";
  $file_types{$filen} = $file_type;
  untie %file_types;
}


# Parse uploaded file, and return its file type 
sub file_cat
{
  my ($upl_dir,$filen,$q) = @_;
  my $file_type;
  
  my $abrack = 0;
  my $abrack_sc = 0;
  my $ast = 0;
  my $str = 0;
  my $str_ents = '';
  open FILE, "<$upl_dir/$filen" or die "Cannot open $filen: $!";
  while (<FILE>)
  {
     s/\s+$//;
     if ( /^>/ )                     { $abrack++; }
     if ( /^atom/i && $abrack == 0 ) { return 'str'; } #pdb file
     if ( /^>\w\w;/ )                { $abrack_sc++; }
     if ( /\*$/ )                    { $ast++; }
     if ( /^structure/i )            
     { 
        $str++; 
	if ( $str_ents ne '' ) { $str_ents .= "_$."; }    #save line no
	else                   { $str_ents = "$."; }     #save line no
     }
  }
  close FILE;
     
  # if neither pdb nor ali file - make this nicer than an error 
  if ($abrack == 0)
  {
     throw saliweb::frontend::InputValidationError(
                "Not correct PDB, pir or fasta format");
  }
  # else ali file; check format - PIR or fasta
  elsif ($abrack_sc == $abrack && $ast >= $abrack)  #PIR
  {
     if ($str == $abrack)  #all structures
     { 
        $file_type = "pir-$abrack-$str_ents-st";
     }   
     elsif ($str > 0)  # some strs some seqs 
     {
        $file_type = "pir-$abrack-$str_ents-stse";
     }
     else    # only seqs
     {	
        $file_type = "pir-$abrack-se";
     }   
  }	
  else   #FASTA
  {
     $file_type = "fasta-$abrack";
  }	
  return $file_type;
}  
  

# Go through all user input and predict what he wants to do
# note that all checks can be done with $upl_count > 0 
# instead of all exists statements. perhaps more stable as no accidental 
# key definitions will matter.
sub guess
{
  my $upl_files_ref = shift;
  my $lib_PDBs_ref = shift;
  my $upld_pseqs = shift;            # no of pasted seqs
  my $upl_count = shift;             # counts for all uploaded file types
  my %upl_files = %$upl_files_ref;   # uploaded files and their types
  my %lib_PDBs = %$lib_PDBs_ref;     # PDBs chosen from SALIGN PDB library 
  my $choice;

  # only strs input 
  if ( !exists $upl_files{'ali_stse'} && !exists $upl_files{'ali_seq'} &&
       $upld_pseqs == 0 )
  {
     #ADD A CHECK HERE WHERE YOU GIVE AN ERROR IF NO STRS EXIST EITHER
     #MAYBE NOT NECESSARY. CAN IT HAPPEN?
     $choice = 'str-str';
  }
  # only seqs input
  elsif ( !exists $upl_files{'ali_stse'} && !exists $upl_files{'str'} &&
          !exists $upl_files{'ali_st'} && !exists $lib_PDBs{'man'} )
  {
     my $input_sets;
     if ( $upld_pseqs > 0 ) { $input_sets = $upl_count->{'ali_seq'} + 1; }
     else                   { $input_sets = $upl_count->{'ali_seq'};     }
     if ( $input_sets == 2 ) { $choice = '2s_seq-seq'; }
     else                    { $choice = '1s_seq-seq'; }
  }
  # mixture of sequences and structures
  else
  {
     my $pseqs_bool;   # 0 if no pasted seqs, 1 if >0
     if ( $upld_pseqs > 0 ) { $pseqs_bool = 1; }
     else                   { $pseqs_bool = 0; }
     # assign no of (sequence ali sets + str-seq ali sets)
     my $seq_stse_sets = $upl_count->{'ali_seq'} + $pseqs_bool;
     $seq_stse_sets += $upl_count->{'ali_stse'};
     	
     if ( $seq_stse_sets == 2 && !exists $upl_files{'str'} &&
          !exists $upl_files{'ali_st'} && !exists $lib_PDBs{'man'} )
     { 
        $choice = '2s_seq-seq';
     }	
     else { $choice = 'str-seq'; }
  }
  return ( $choice );
}


# Check ali structure entries - do the structures exist?
# The following str file names correspond to a structure ali entry named XXXX:
# pdbXXXX.ent pdbXXXX.pdb pdbXXXX XXXX.ent XXXX.pdb and XXXX
sub chk_alistrs
{
  my $upl_files_ref = shift;
  my $upl_count_ref = shift;
  my $job_dir = shift;
  my $lib_PDBs_ref = shift;
  my $upl_dir = shift;
  my %upl_files = %$upl_files_ref;
  my %upl_count = %$upl_count_ref;
  my %lib_PDBs = %$lib_PDBs_ref;
  
  my %changes;

  if ( exists $upl_files{'ali_st'} )
  {
     foreach my $filen ( keys %{ $upl_files{'ali_st'} } )
     {
        my @rej;
        my @pass;
        open FILE, "<$upl_dir/$filen" or die "Cannot open $filen: $!";
        while (<FILE>)
        {
           if ( /^structure/i )
	   { 
	      my @str_info = split /:/;
	      if ( $#str_info < 5 ) { next; }   #skip if incorrect format
	      #strip leading and trailing whitespaces
	      foreach my $i ( 1 .. 5 )
	      {
	         $str_info[$i] =~ s/^\s+//;
	         $str_info[$i] =~ s/\s+$//;
	      }
	      my $pdb_code = $str_info[1];
	      my $bounds = "$str_info[2]:$str_info[3]:$str_info[4]:$str_info[5]";

	      # check if str file exists or not for entry
	      #KANSKE BORDE DU HAR INTE GORA UPL FILES ANDRINGARNA I REALTID.
	      #1) SMIDIGARE - SLIPPER KOLLA BADE STR OCH USED_STR
	      if ( exists $upl_files{'str'} )
	      {
	         if ( exists $upl_files{'str'}{"pdb$pdb_code.ent"} )
	         {
                    push @pass, $.;
		    # Move str file entry to mark that it is used by an ali file
		    push @{ $upl_files{'used_str'}{"pdb$pdb_code.ent"} }, $bounds;
                    $upl_count{'used_str'}++;
                    delete ( $upl_files{'str'}{"pdb$pdb_code.ent"} );
		    $upl_count{'str'}--;
		    next;
	         }
	         elsif ( exists $upl_files{'str'}{"pdb$pdb_code.pdb"} ) 
	         {
                    push @pass, $.;
		    # Move str file entry to mark that it is used by an ali file
		    push @{ $upl_files{'used_str'}{"pdb$pdb_code.pdb"} }, $bounds; 
                    $upl_count{'used_str'}++;
                    delete ( $upl_files{'str'}{"pdb$pdb_code.pdb"} );
		    $upl_count{'str'}--;
		    next;
	         }
	         elsif ( exists $upl_files{'str'}{"pdb$pdb_code"} )
	         {
                    push @pass, $.;
		    # Move str file entry to mark that it is used by an ali file
		    push @{ $upl_files{'used_str'}{"pdb$pdb_code"} }, $bounds; 
                    $upl_count{'used_str'}++;
                    delete ( $upl_files{'str'}{"pdb$pdb_code"} );
		    $upl_count{'str'}--;
		    next;
	         }
                 elsif ( exists $upl_files{'str'}{"$pdb_code.ent"} )
	         {
                    push @pass, $.;
		    # Move str file entry to mark that it is used by an ali file
		    push @{ $upl_files{'used_str'}{"$pdb_code.ent"} }, $bounds; 
                    $upl_count{'used_str'}++;
                    delete ( $upl_files{'str'}{"$pdb_code.ent"} );
		    $upl_count{'str'}--;
		    next;
	         }
	         elsif ( exists $upl_files{'str'}{"$pdb_code.pdb"} )
	         {
                    push @pass, $.;
		    # Move str file entry to mark that it is used by an ali file
		    push @{ $upl_files{'used_str'}{"$pdb_code.pdb"} }, $bounds; 
                    $upl_count{'used_str'}++;
                    delete ( $upl_files{'str'}{"$pdb_code.pdb"} );
		    $upl_count{'str'}--;
		    next;
	         }
	         elsif ( exists $upl_files{'str'}{"$pdb_code"} ) 
	         {
                    push @pass, $.;
		    # Move str file entry to mark that it is used by an ali file
		    push @{ $upl_files{'used_str'}{$pdb_code} }, $bounds; 
                    $upl_count{'used_str'}++;
                    delete ( $upl_files{'str'}{$pdb_code} );
		    $upl_count{'str'}--;
		    next;
	         }
	      }
	      if ( exists $upl_files{'used_str'} )
	      {
		 if ( exists $upl_files{'used_str'}{"pdb$pdb_code.ent"} )
	         {
                    push @pass, $.;
		    push @{ $upl_files{'used_str'}{"pdb$pdb_code.ent"} }, $bounds;
		    next;
	         }
	         elsif ( exists $upl_files{'used_str'}{"pdb$pdb_code.pdb"} ) 
	         {
                    push @pass, $.;
		    push @{ $upl_files{'used_str'}{"pdb$pdb_code.pdb"} }, $bounds; 
		    next;
	         }
	         elsif ( exists $upl_files{'used_str'}{"pdb$pdb_code"} )
	         {
                    push @pass, $.;
		    push @{ $upl_files{'used_str'}{"pdb$pdb_code"} }, $bounds; 
		    next;
	         }
                 elsif ( exists $upl_files{'used_str'}{"$pdb_code.ent"} )
	         {
                    push @pass, $.;
		    push @{ $upl_files{'used_str'}{"$pdb_code.ent"} }, $bounds; 
		    next;
	         }
	         elsif ( exists $upl_files{'used_str'}{"$pdb_code.pdb"} )
	         {
                    push @pass, $.;
		    push @{ $upl_files{'used_str'}{"$pdb_code.pdb"} }, $bounds; 
		    next;
	         }
	         elsif ( exists $upl_files{'used_str'}{"$pdb_code"} ) 
	         {
                    push @pass, $.;
		    push @{ $upl_files{'used_str'}{$pdb_code} }, $bounds; 
		    next;
	         }
	      }
              if (pdb_code_exists($pdb_code))
	      {	      
	         push @{ $lib_PDBs{'ali'}{$pdb_code} }, $bounds;
                 push @pass, $.;
		 next;
	      }
	      push @rej, $.;
	   }
        }
        close FILE;
	# if false structure entries exist correct this 
	if ( $#rej > -1 )
	{
	   if ( $#pass > -1 )    # some strs passed
	   {
	      my $str_ents = join("_",@pass);
	      my $length = $upl_files{'ali_st'}{$filen}{'length'};
              my $file_type = "pir-$length-$str_ents-stse";
	      #change in DBM entry
              add_to_DBM($filen,$file_type,$job_dir); 
              #temp save to change in %upl_files when finished checking
	      $changes{'st'}{$filen}{'type'} = 'stse';
	      @{ $changes{'st'}{$filen}{'st_ents'} } = @pass;
	   } 
	   else   # oops, they're all false
	   {
	      my $length = $upl_files{'ali_st'}{$filen}{'length'};
              my $file_type = "pir-$length-se";
	      #change in DBM entry
              add_to_DBM($filen,$file_type,$job_dir); 
              #temp save to change in %upl_files when finished checking
	      $changes{'st'}{$filen}{'type'} = 'se';
	   }
	}
     }
  }
  if ( exists $upl_files{'ali_stse'} )
  {
     foreach my $filen ( keys %{ $upl_files{'ali_stse'} } )
     {
  	my @rej;
        my @pass;
        open FILE, "<$upl_dir/$filen" or die "Cannot open $filen: $!";
        while (<FILE>)
        {
           if ( /^structure/i )
	   { 
	      my @str_info = split /:/;
	      if ( $#str_info < 5 ) { next; }   #skip if incorrect format
	      #strip leading and trailing whitespaces
	      foreach my $i ( 1 .. 5 )
	      {
	         $str_info[$i] =~ s/^\s+//;
	         $str_info[$i] =~ s/\s+$//;
	      }
	      my $pdb_code = $str_info[1];
	      my $bounds = "$str_info[2]:$str_info[3]:$str_info[4]:$str_info[5]";
	      # mark if str file exists or not for entry
	      if ( exists $upl_files{'str'} )
	      {
	         if ( exists $upl_files{'str'}{"pdb$pdb_code.ent"} )
	         {
                    push @pass, $.;
		    # Move str file entry to mark that it is used by an ali file
		    push @{ $upl_files{'used_str'}{"pdb$pdb_code.ent"} }, $bounds; 
                    $upl_count{'used_str'}++;
                    delete ( $upl_files{'str'}{"pdb$pdb_code.ent"} );
		    $upl_count{'str'}--;
		    next;
	         }
	         elsif ( exists $upl_files{'str'}{"pdb$pdb_code.pdb"} ) 
	         {
                    push @pass, $.;
		    # Move str file entry to mark that it is used by an ali file
		    push @{ $upl_files{'used_str'}{"pdb$pdb_code.pdb"} }, $bounds; 
                    $upl_count{'used_str'}++;
                    delete ( $upl_files{'str'}{"pdb$pdb_code.pdb"} );
		    $upl_count{'str'}--;
		    next;
	         }
	         elsif ( exists $upl_files{'str'}{"pdb$pdb_code"} )
	         {
                    push @pass, $.;
		    # Move str file entry to mark that it is used by an ali file
		    push @{ $upl_files{'used_str'}{"pdb$pdb_code"} }, $bounds; 
                    $upl_count{'used_str'}++;
                    delete ( $upl_files{'str'}{"pdb$pdb_code"} );
		    $upl_count{'str'}--;
		    next;
	         }
                 elsif ( exists $upl_files{'str'}{"$pdb_code.ent"} )
	         {
                    push @pass, $.;
		    # Move str file entry to mark that it is used by an ali file
		    push @{ $upl_files{'used_str'}{"$pdb_code.ent"} }, $bounds; 
                    $upl_count{'used_str'}++;
                    delete ( $upl_files{'str'}{"$pdb_code.ent"} );
		    $upl_count{'str'}--;
		    next;
	         }
	         elsif ( exists $upl_files{'str'}{"$pdb_code.pdb"} )
	         {
                    push @pass, $.;
		    # Move str file entry to mark that it is used by an ali file
		    push @{ $upl_files{'used_str'}{"$pdb_code.pdb"} }, $bounds; 
                    $upl_count{'used_str'}++;
                    delete ( $upl_files{'str'}{"$pdb_code.pdb"} );
		    $upl_count{'str'}--;
		    next;
	         }
	         elsif ( exists $upl_files{'str'}{"$pdb_code"} ) 
	         {
                    push @pass, $.;
		    # Move str file entry to mark that it is used by an ali file
		    push @{ $upl_files{'used_str'}{$pdb_code} }, $bounds; 
                    $upl_count{'used_str'}++;
                    delete ( $upl_files{'str'}{$pdb_code} );
		    $upl_count{'str'}--;
		    next;
	         }
	      }
	      if ( exists $upl_files{'used_str'} )
	      {
		 if ( exists $upl_files{'used_str'}{"pdb$pdb_code.ent"} )
	         {
                    push @pass, $.;
		    push @{ $upl_files{'used_str'}{"pdb$pdb_code.ent"} }, $bounds;
		    next;
	         }
	         elsif ( exists $upl_files{'used_str'}{"pdb$pdb_code.pdb"} ) 
	         {
                    push @pass, $.;
		    push @{ $upl_files{'used_str'}{"pdb$pdb_code.pdb"} }, $bounds; 
		    next;
	         }
	         elsif ( exists $upl_files{'used_str'}{"pdb$pdb_code"} )
	         {
                    push @pass, $.;
		    push @{ $upl_files{'used_str'}{"pdb$pdb_code"} }, $bounds; 
		    next;
	         }
                 elsif ( exists $upl_files{'used_str'}{"$pdb_code.ent"} )
	         {
                    push @pass, $.;
		    push @{ $upl_files{'used_str'}{"$pdb_code.ent"} }, $bounds; 
		    next;
	         }
	         elsif ( exists $upl_files{'used_str'}{"$pdb_code.pdb"} )
	         {
                    push @pass, $.;
		    push @{ $upl_files{'used_str'}{"$pdb_code.pdb"} }, $bounds; 
		    next;
	         }
	         elsif ( exists $upl_files{'used_str'}{"$pdb_code"} ) 
	         {
                    push @pass, $.;
		    push @{ $upl_files{'used_str'}{$pdb_code} }, $bounds; 
		    next;
	         }
	      }
              if (pdb_code_exists($pdb_code))
	      {	      
	         push @{ $lib_PDBs{'ali'}{$pdb_code} }, $bounds;
                 push @pass, $.;
		 next;
	      }
	      push @rej, $.;
	   }
        }
        close FILE;
        # if false structure entries exist correct this 
        if ( $#rej > -1 )
	{
	   if ( $#pass > -1 )    # some strs passed
	   {
	      my $str_ents = join("_",@pass);
	      my $length = $upl_files{'ali_stse'}{$filen}{'length'};
              my $file_type = "pir-$length-$str_ents-stse";
	      #change in DBM entry
              add_to_DBM($filen,$file_type,$job_dir); 
              #temp save to change in %upl_files when finished checking
	      $changes{'stse'}{$filen}{'type'} = 'stse';
	      @{ $changes{'stse'}{$filen}{'st_ents'} } = @pass;
	   } 
	   else   # oops, they're all false
	   {
	      my $length = $upl_files{'ali_stse'}{$filen}{'length'};
              my $file_type = "pir-$length-se";
	      #change in DBM entry
              add_to_DBM($filen,$file_type,$job_dir); 
              #temp save to change in %upl_files when finished checking
	      $changes{'stse'}{$filen}{'type'} = 'se';
	   }
	}
     }
  }

  #implement changes saved in %changes ie fix %upl_files and %upl_count
  if ( exists $changes{'st'} )
  {
     foreach my $filen ( keys %{ $changes{'st'} } )
     {
	if ( $changes{'st'}{$filen}{'type'} eq 'stse' )
	{
 	   $upl_files{'ali_stse'}{$filen}{'length'} = $upl_files{'ali_st'}{$filen}{'length'};
	   @{ $upl_files{'ali_stse'}{$filen}{'st_ents'} } = @{ $changes{'st'}{$filen}{'st_ents'} };
	   # delete old entry
	   delete ( $upl_files{'ali_st'}{$filen} );
	   $upl_count{'ali_st'}--;
	   $upl_count{'ali_stse'}++;
	}
	else
	{
	   $upl_files{'ali_seq'}{$filen}{'format'} = 'pir';
	   $upl_files{'ali_seq'}{$filen}{'length'} = $upl_files{'ali_st'}{$filen}{'length'};
	   delete ( $upl_files{'ali_st'}{$filen} );
	   $upl_count{'ali_st'}--;
	   $upl_count{'ali_seq'}++;
	}
     }
     # delete superkey ali_st if no ali_st files left
     if ( $upl_count{'ali_st'} == 0 )
     {
        delete ( $upl_files{'ali_st'} );
     }   
  }
  if ( exists $changes{'stse'} )
  {
     foreach my $filen ( keys %{ $changes{'stse'} } )
     {
	if ( $changes{'stse'}{$filen}{'type'} eq 'stse' )
	{
	   @{ $upl_files{'ali_stse'}{$filen}{'st_ents'} } = @{ $changes{'stse'}{$filen}{'st_ents'} };
	}
	else
	{
	   $upl_files{'ali_seq'}{$filen}{'format'} = 'pir';
	   $upl_files{'ali_seq'}{$filen}{'length'} = $upl_files{'ali_stse'}{$filen}{'length'};
	   delete ( $upl_files{'ali_stse'}{$filen} );
	   $upl_count{'ali_stse'}--;
	   $upl_count{'ali_seq'}++;
	}
     }
     # delete superkey ali_stse if no ali_stse files left
     if ( $upl_count{'ali_stse'} == 0 )
     {
        delete ( $upl_files{'ali_stse'} );
     }   
  }
  # delete superkey str if all have been moved to used_str
  if ( $upl_count{'str'} == 0 )
  {
     delete ( $upl_files{'str'} );
  }   
  return ( \%upl_files,\%upl_count,\%lib_PDBs );
}


# generate default structure-structure alignment form page
# on submission of this form SALIGN will do a multiple structure alignment
# 2-30 segments => tree, >30 segments => progressive
sub str_str
{
  my $self = shift;
  my $q = shift;
  my $email = shift;
  my $upl_files_ref = shift;
  my $lib_PDBs_ref = shift;
  my $job_name = shift;
  my %upl_files = %$upl_files_ref;
  my %lib_PDBs = %$lib_PDBs_ref;
  
  my $msg = print_cont1_category_choice ($self, $q, "Structure-structure alignment");
  $msg .=	$q->start_form( -method => "post", -action => $self->submit_url ).
 	$q->hidden( -name => "tool", -default => "str_str", -override => 1).
        $q->hidden( -name => "job_name", -default => $job_name, -override => 1).
	$q->hidden( -name => "email", -default => $email, -override => 1);

  $msg .= "Specified structure segments will be multiply aligned.<br /><br />";
  $msg .= "\n<table> <col width=\"100\"><col width=\"100\">\n";
  $msg .= print_pdb_segments ($self, $q, $upl_files_ref, $lib_PDBs_ref);
  $msg .= "<tr><td>\n";

#  # Show uploaded ali files - do we want this or not?
#  if ( exists $upl_files{'ali_st'} )
#  {
#     print $q->p("Uploaded structure alignment files");
#     foreach my $filen ( keys %{ $upl_files{'ali_st'} } )
#     {
#        print $q->p( $filen );
#     }   
#  }
  $msg .= $q->hidden( -name => "align_type", -default => "automatic", -override => 1 ).
        $q->hidden( -name => "1D_open_stst", -default => "-150", -override => 1 ).
	$q->hidden( -name => "1D_elong_stst", -default => "-50", -override => 1 ).
	$q->hidden( -name => "3D_open", -default => "0", -override => 1 ).
	$q->hidden( -name => "3D_elong", -default => "2", -override => 1 ).
	$q->hidden( -name => "fw_1", -default => "1", -override => 1 ).
	$q->hidden( -name => "fw_2", -default => "1", -override => 1 ).
	$q->hidden( -name => "fw_3", -default => "1", -override => 1 ).
	$q->hidden( -name => "fw_4", -default => "1", -override => 1 ).
	$q->hidden( -name => "fw_5", -default => "1", -override => 1 ).
	$q->hidden( -name => "fw_6", -default => "0", -override => 1 ).
	$q->hidden( -name => "max_gap", -default => "20", -override => 1 ).
	$q->hidden( -name => "RMS_cutoff", -default => "3.5", -override => 1 ).
	$q->hidden( -name => "overhangs", -default => "0", -override => 1 ).
	$q->hidden( -name => "fit", -default => "True", -override => 1 ).
	$q->hidden( -name => "improve", -default => "True", -override => 1 ).
	$q->hidden( -name => "write_whole", -default => "False", -override => 1 ).
	$q->hidden( -name => "gap-gap_score", -default => "0", -override => 1 ).
	$q->hidden( -name => "gap-res_score", -default => "0", -override => 1 ).
	$q->br.
	$q->submit( -value => "Submit" ).
	$q->reset().
	$q->br.
	$q->end_form();
  
  # form for call to advanced view
  $msg .= $q->start_form( -method => "get" ).
        $q->hidden( -name => "caller", -default => "str-str", -override => 1 ).
	$q->hidden( -name => "job_name", -default => $job_name, -override => 1).
	$q->hidden( -name => "email", -default => $email, -override => 1);
  if ( exists $upl_files{'str'} )
  {
     foreach my $filen ( keys %{ $upl_files{'str'} } )
     {
        $msg .= $q->hidden( 
	        -name => "uplsegm_$filen", 
		-default => 'FIRST:@:LAST:@',
		-override => 1
	      );
     }
  } 
  if ( exists $upl_files{'used_str'} )
  {
     foreach my $filen ( keys %{ $upl_files{'used_str'} } )
     {
        # Get default segments
        my $default = join "\n", @{ $upl_files{'used_str'}{$filen} };
        $msg .= $q->hidden( 
                -name => "uplsegm_$filen",
	        -default => $default,
		-override => 1
	      );
     }
  }
  if ( exists $lib_PDBs{'man'} )
  {
     foreach my $pdb ( keys %{ $lib_PDBs{'man'} } )
     {
        # skip if same pdb exists in ali file entry
        if ( exists $lib_PDBs{'ali'} )
	{
	   if ( exists $lib_PDBs{'ali'}{$pdb} ) { next; }
        }
        $msg .= $q->hidden(
                -name => "libsegm_$pdb", 
	        -default => 'FIRST:@:LAST:@',
         	-override => 1
              );
     }
  }   
  if ( exists $lib_PDBs{'ali'} )
  {
     foreach my $pdb ( keys %{ $lib_PDBs{'ali'} } )
     {
        # Get default segments
        my $default = join "\n", @{ $lib_PDBs{'ali'}{$pdb} };
        $msg .= $q->hidden( 
	        -name => "libsegm_$pdb",
	        -default => $default,
	        -override => 1
	      );
     }
  }
  $msg .= $q->submit( -name => "state", -value => "Advanced" ),
	$q->end_form();

  $msg .= "</td></tr></table>\n";
  return $msg;

}

# generate default structure-sequence alignment form page
# when submitted SALIGN will first align all sequences and all
# structures independently and then align the two alignments to
# each other with a str-seq or profile-profile alignment. 
# step 1: strs: 2-30 tree, >30 progressive
#         seqs: 2-30 tree, 31-500 progressive, >500 no realignment
# step 2: prof-prof if >100 entries in both step 1 alignments
#         else str-seq
sub str_seq
{
  my $self = shift;
  my $q = shift;
  my $email = shift;
  my $upl_files_ref = shift;
  my $lib_PDBs_ref = shift;
  my $upld_pseqs = shift;
  my $job_name = shift;
  my %upl_files = %$upl_files_ref;
  my %lib_PDBs = %$lib_PDBs_ref;
  
# Start html
  my $msg = print_cont1_category_choice ($self, $q, "Structure-sequence alignment");
  $msg .= $q->start_form( -method => "post", -action => $self->submit_url ).
	$q->hidden( -name => "tool", -default => "str_seq", -override => 1).
        $q->hidden( -name => "job_name", -default => $job_name, -override => 1).
	$q->hidden( -name => "email", -default => $email, -override => 1).
	$q->hidden( -name => "upld_pseqs", -default => $upld_pseqs, -override => 1);

  $msg .= "Step 1: Structures and sequences will be multiply aligned independently.<br />";
  $msg .= "Step 2: The resulting alignments from step 1 will be aligned to each other.<br /><br />";

  $msg .= "\n<table> <col width=\"100\"><col width=\"100\">\n";

  $msg .= print_pdb_segments ($self, $q, $upl_files_ref, $lib_PDBs_ref);

  $msg .= "<tr><td>&nbsp;</td><td>\n";

  # Show uploaded ali files and no of pasted seqs
  if ( exists $upl_files{'ali_st'} || exists $upl_files{'ali_stse'} ||
       exists $upl_files{'ali_seq'} )
  {
     $msg .= $q->p("Uploaded alignment files");
     my @ali_cats = qw( ali_st ali_stse ali_seq );
     foreach my $ali_cat ( @ali_cats )
     {
        if ( exists $upl_files{$ali_cat} )
        {
           foreach my $filen ( keys %{ $upl_files{$ali_cat} } )
           {
	      $msg .= $q->p( $filen );
           }   
        }
     }   
  }
  if ($upld_pseqs > 0) {
     if ($upld_pseqs == 1) {
	$msg .= $q->p("$upld_pseqs pasted sequence uploaded");
     }
     else {
	$msg .= $q->p("$upld_pseqs pasted sequences uploaded");
     }
  }
# alignment type, ie progressive or tree, should be set in form_proc.pl
# once it is clear how many segments there are
# In advanced the user should only be able to do one 1Dchange and it will
# set all 1D gap pens to that value
  $msg .=	$q->hidden( -name => "align_type", -default => "automatic", -override => 1 ).
        $q->hidden( -name => "1D_open_stst", -default => "-150", -override => 1 ).
	$q->hidden( -name => "1D_elong_stst", -default => "-50", -override => 1 ).
	$q->hidden( -name => "1D_open_stse", -default => "-100", -override => 1).
	$q->hidden( -name => "1D_elong_stse", -default => "0", -override => 1).
        $q->hidden( -name => "1D_open_sese", -default => "-450", -override => 1).
	$q->hidden( -name => "1D_elong_sese", -default => "-50", -override => 1).
        $q->hidden( -name => "1D_open_prof", -default => "-300", -override => 1).
	$q->hidden( -name => "1D_elong_prof", -default => "0", -override => 1).
	$q->hidden( -name => "2D_1", -default => "3.5", -override => 1).
	$q->hidden( -name => "2D_2", -default => "3.5", -override => 1).
	$q->hidden( -name => "2D_3", -default => "3.5", -override => 1).
	$q->hidden( -name => "2D_4", -default => "0.2", -override => 1).
	$q->hidden( -name => "2D_5", -default => "4.0", -override => 1).
	$q->hidden( -name => "2D_6", -default => "6.5", -override => 1).
	$q->hidden( -name => "2D_7", -default => "2.0", -override => 1).
	$q->hidden( -name => "2D_8", -default => "0.0", -override => 1).
	$q->hidden( -name => "2D_9", -default => "0", -override => 1).
	$q->hidden( -name => "3D_open", -default => "0", -override => 1 ).
	$q->hidden( -name => "3D_elong", -default => "2", -override => 1 ).
	$q->hidden( -name => "fw_1", -default => "1", -override => 1 ).
	$q->hidden( -name => "fw_2", -default => "1", -override => 1 ).
	$q->hidden( -name => "fw_3", -default => "1", -override => 1 ).
	$q->hidden( -name => "fw_4", -default => "1", -override => 1 ).
	$q->hidden( -name => "fw_5", -default => "1", -override => 1 ).
	$q->hidden( -name => "fw_6", -default => "0", -override => 1 ).
	$q->hidden( -name => "max_gap", -default => "20", -override => 1 ).
	$q->hidden( -name => "RMS_cutoff", -default => "3.5", -override => 1 ).
	$q->hidden( -name => "overhangs", -default => "0", -override => 1 ).
	$q->hidden( -name => "fit", -default => "True", -override => 1 ).
	$q->hidden( -name => "improve", -default => "True", -override => 1 ).
	$q->hidden( -name => "write_whole", -default => "False", -override => 1 ).
	$q->hidden( -name => "gap-gap_score", -default => "0", -override => 1 ).
	$q->hidden( -name => "gap-res_score", -default => "0", -override => 1 ).
	$q->br.
	$q->submit( -value => "Submit" ).
	$q->reset().
	$q->br.
	$q->end_form();
	
  # create form to call advanced view
  $msg .= $q->start_form( -method => "get" ).
        $q->hidden( -name => "caller", -default => "str-seq", -override => 1 ).
	$q->hidden( -name => "upld_pseqs", -default => $upld_pseqs, -override => 1).
	$q->hidden( -name => "job_name", -default => $job_name, -override => 1).
	$q->hidden( -name => "email", -default => $email, -override => 1);
  # pass default structure segments
  if ( exists $upl_files{'str'} )
  {
     foreach my $filen ( keys %{ $upl_files{'str'} } )
     {
        $msg .= $q->hidden( 
	        -name => "uplsegm_$filen", 
		-default => 'FIRST:@:LAST:@',
		-override => 1
	      );
     }
  } 
  if ( exists $upl_files{'used_str'} )
  {
     foreach my $filen ( keys %{ $upl_files{'used_str'} } )
     {
        # Get default segments
        my $default = join "\n", @{ $upl_files{'used_str'}{$filen} };
        $msg .= $q->hidden( 
                -name => "uplsegm_$filen",
	        -default => $default,
		-override => 1
	      );
     }
  }
  if ( exists $lib_PDBs{'man'} )
  {
     foreach my $pdb ( keys %{ $lib_PDBs{'man'} } )
     {
        # skip if same pdb exists in ali file entry
        if ( exists $lib_PDBs{'ali'} )
	{
	   if ( exists $lib_PDBs{'ali'}{$pdb} ) { next; }
        }
        $msg .= $q->hidden(
                -name => "libsegm_$pdb", 
	        -default => 'FIRST:@:LAST:@',
         	-override => 1
              );
     }
  }   
  if ( exists $lib_PDBs{'ali'} )
  {
     foreach my $pdb ( keys %{ $lib_PDBs{'ali'} } )
     {
        # Get default segments
        my $default = join "\n", @{ $lib_PDBs{'ali'}{$pdb} };
        $msg .= $q->hidden( 
	        -name => "libsegm_$pdb",
	        -default => $default,
	        -override => 1
	      );
     }
  }
  # pass uploaded ali files 
  my $ali_files = '';
  my @ali_cats = qw( ali_st ali_stse ali_seq ); 
  foreach my $ali_cat ( @ali_cats )
  {
     if ( exists $upl_files{$ali_cat} )
     {
        foreach my $filen ( keys %{ $upl_files{$ali_cat} } )
        {
           $ali_files .= "$filen ";
        }   
     }
  }   
  $ali_files =~ s/\s$//;
  $msg .= $q->hidden( -name => "ali_files", -default => $ali_files, -override => 1 );
  $msg .= $q->submit( -name => "state", -value => "Advanced" ).
	$q->end_form();

  $msg .= "</td></tr>\n";
  $msg .= "</table>\n";
  return $msg;
}


# generate default 2-step sequence-sequence alignment form page
# when submitted SALIGN will first align the two sets of
# sequences independently and then align the two alignments to
# each other using a profile-profile alignment. 
# step 1; for each set: 
# no of seqs: 2-30 => tree, 31-500 => progressive, >500 => no realignment
sub twostep_sese
{
  my $self = shift;
  my $q = shift;
  my $email = shift;
  my $upl_files_ref = shift;
  my $upld_pseqs = shift;
  my $job_name = shift;
  my $lib_PDBs_ref = shift;
  my %upl_files = %$upl_files_ref;
  my %lib_PDBs = %$lib_PDBs_ref;
  
  my $msg = print_cont1_category_choice ($self, $q, "Sequence-sequence alignment");
  $msg .= $q->start_form( -method => "post", -action => $self->submit_url ).
	$q->hidden( -name => "tool", -default => "2s_sese", -override => 1).
        $q->hidden( -name => "job_name", -default => $job_name, -override => 1).
	$q->hidden( -name => "email", -default => $email, -override => 1).
	$q->hidden( -name => "upld_pseqs", -default => $upld_pseqs, -override => 1);

  $msg .= "Step 1: The two sets of sequences will be multiply aligned independently.<br />";
  $msg .= "Step 2: The resulting alignments from step 1 will be aligned to each other.<br /><br />";

  # Show uploaded ali files and no of pasted seqs
  $msg .= $q->p("Uploaded alignment files");
  if ( exists $upl_files{'ali_stse'} )
  {
     foreach my $filen ( keys %{ $upl_files{'ali_stse'} } )
     {
        $msg .= $q->p( $filen );
     }   
  }
  if ( exists $upl_files{'ali_seq'} )
  {
     foreach my $filen ( keys %{ $upl_files{'ali_seq'} } )
     {
	$msg .= $q->p( $filen );
     }   
  }
  if ($upld_pseqs > 0)
  {
     if ($upld_pseqs == 1)
     {
	$msg .= $q->p("$upld_pseqs pasted sequence uploaded");
     }
     else
     {
	$msg .= $q->p("$upld_pseqs pasted sequences uploaded");
     }
  }
  $msg .=	$q->hidden( -name => "align_type", -default => "automatic",
          -override => 1 ).
        $q->hidden( -name => "1D_open_sese", -default => "-450",
	  -override => 1 ).
	$q->hidden( -name => "1D_elong_sese", -default => "-50",
	  -override => 1 ).
        $q->hidden( -name => "1D_open_prof", -default => "-300",
	  -override => 1).
	$q->hidden( -name => "1D_elong_prof", -default => "0",
	  -override => 1).
	$q->hidden( -name => "overhangs", -default => "0",
	  -override => 1 ).
	$q->hidden( -name => "improve", -default => "True",
	  -override => 1 ).
	$q->hidden( -name => "gap-gap_score", -default => "0",
	  -override => 1 ).
	$q->hidden( -name => "gap-res_score", -default => "0",
	  -override => 1 ).
	$q->br.
	$q->submit( -value => "Submit" ).
	$q->reset().
	$q->br.
	$q->end_form();
	
  # create form to call advanced view
  $msg .= $q->start_form( -method => "get" ).
	$q->hidden( -name => "caller", -default => "2s_sese",
	  -override => 1 ).
	$q->hidden( -name => "upld_pseqs", -default => $upld_pseqs,
          -override => 1).
	$q->hidden( -name => "job_name", -default => $job_name,
          -override => 1).
	$q->hidden( -name => "email", -default => $email,
          -override => 1);
  my $structures = 0;	  
  # pass default structure segments if any
  if ( exists $upl_files{'used_str'} )
  {
     foreach my $filen ( keys %{ $upl_files{'used_str'} } )
     {
        # Get default segments
        my $default = join "\n", @{ $upl_files{'used_str'}{$filen} };
        $msg .= $q->hidden( 
                -name => "uplsegm_$filen",
	        -default => $default,
		-override => 1
	      );
     }
     $structures = 1;
  }
  if ( exists $lib_PDBs{'ali'} )
  {
     foreach my $pdb ( keys %{ $lib_PDBs{'ali'} } )
     {
        # Get default segments
        my $default = join "\n", @{ $lib_PDBs{'ali'}{$pdb} };
        $msg .= $q->hidden( 
	        -name => "libsegm_$pdb",
	        -default => $default,
	        -override => 1
	      );
     }
     $structures = 1;
  }
  # pass uploaded ali files 
  my $ali_files = '';
  my @ali_cats = qw( ali_stse ali_seq ); 
  foreach my $ali_cat ( @ali_cats )
  {
     if ( exists $upl_files{$ali_cat} )
     {
        foreach my $filen ( keys %{ $upl_files{$ali_cat} } )
        {
           $ali_files .= "$filen ";
        }   
     }
  }   
  $ali_files =~ s/\s$//;
  $msg .= $q->hidden( -name => "ali_files", -default => $ali_files,
          -override => 1 ).
	$q->hidden( -name => "structures", -default => $structures,
	  -override => 1 ).
        $q->submit( -name => "state", -value => "Advanced" ).
	$q->end_form();

  return $msg;
}

# generate default 1-step sequence-sequence alignment form page
# when submitted SALIGN will perform a multiple alignment of all the
# sequences using a substitution matrix.
# no of seqs: 2-30 => tree, >30 => progressive
sub onestep_sese
{
  my $self = shift;
  my $q = shift;
  my $email = shift;
  my $upl_files_ref = shift;
  my $upld_pseqs = shift;
  my $job_name = shift;
  my %upl_files = %$upl_files_ref;

  my $msg = print_cont1_category_choice ($self, $q, "Sequence-sequence alignment");
  $msg .=$q->start_form( -method => "post", -action => $self->submit_url ).
	$q->hidden( -name => "tool", -default => "1s_sese", -override => 1).
        $q->hidden( -name => "job_name", -default => $job_name, -override => 1).
	$q->hidden( -name => "email", -default => $email, -override => 1).
	$q->hidden( -name => "upld_pseqs", -default => $upld_pseqs, -override => 1);

  $msg .= "All uploaded sequences will be multiply aligned.<br /><br />";

  # Show uploaded ali files and no of pasted seqs
  if ( exists $upl_files{'ali_seq'} )
  {
     $msg .= $q->p("Uploaded alignment files");
     foreach my $filen ( keys %{ $upl_files{'ali_seq'} } )
     {
	$msg .= $q->p( $filen );
     }   
  }
  if ($upld_pseqs > 0)
  {
     if ($upld_pseqs == 1)
     {
	$msg .= $q->p("$upld_pseqs pasted sequence uploaded");
     }
     else
     {
	$msg .= $q->p("$upld_pseqs pasted sequences uploaded");
     }
  }
  $msg .=	$q->hidden( -name => "align_type", -default => "automatic",
          -override => 1 ).
        $q->hidden( -name => "1D_open_sese", -default => "-450",
	  -override => 1 ).
	$q->hidden( -name => "1D_elong_sese", -default => "-50",
	  -override => 1 ).
	$q->hidden( -name => "overhangs", -default => "0",
	  -override => 1 ).
	$q->hidden( -name => "improve", -default => "True",
	  -override => 1 ).
	$q->hidden( -name => "gap-gap_score", -default => "0",
	  -override => 1 ).
	$q->hidden( -name => "gap-res_score", -default => "0",
	  -override => 1 ).
	$q->br.
	$q->submit( -value => "Submit" ).
	$q->reset().
	$q->br.
	$q->end_form();
	
  $msg .= $q->start_form( -method => "get" ).
	$q->hidden( -name => "caller", -default => "1s_sese",
	  -override => 1 ).
	$q->hidden( -name => "upld_pseqs", -default => $upld_pseqs,
          -override => 1).
	$q->hidden( -name => "structures", -default => 0,
	  -override => 1 ).
	$q->hidden( -name => "job_name", -default => $job_name,
          -override => 1).
	$q->hidden( -name => "email", -default => $email,
          -override => 1);
  # pass uploaded ali files 
  my $ali_files = '';
  my $ali_cat = qw( ali_seq ); 
  if ( exists $upl_files{$ali_cat} )
  {
     foreach my $filen ( keys %{ $upl_files{$ali_cat} } )
     {
        $ali_files .= "$filen ";
     }   
  }
  $ali_files =~ s/\s$//;
  $msg .= $q->hidden( -name => "ali_files", -default => $ali_files,
          -override => 1 ),
        $q->submit( -name => "state", -value => "Advanced" ),
	$q->end_form();

  return $msg;
}

# generate advanced structure-structure alignment form page
sub adv_stst
{
  my $self = shift;
  my $q = shift;
  my $job_name = shift;
  my $email = shift;
  my %params; # Fetch all form values from default view.

  foreach my $param_name ($q->param) {
     $params{$param_name} = $q->param($param_name);
  }
 
  my $msg = print_cont1_advance_option ($self, $q);
  $msg .=	$q->start_multipart_form( -method => "post", -action => $self->submit_url ).
 	$q->hidden( -name => "tool", -default => "str_str_adv", -override => 1).
        $q->hidden( -name => "job_name", -default => $job_name, -override => 1).
	$q->hidden( -name => "email", -default => $email, -override => 1);

  $msg .= "<p>Depending on the choice of the alignment category, some options may have no effect.</p>\n";

  $msg .= "<table>\n"
  . print_advance_alignment_category ($self, $q)
  . print_alignment_type ($self, $q)
  . print_advance_pdb_segments ($self, $q, \%params)
  . print_advance_penalties ($self, $q)
  . print_advance_weight ($self, $q)
  . print_advance_rms ($self, $q)
  . print_advance_gap ($self, $q, 1)
  . print_advance_fit ($self, $q)
  . print_advance_improve ($self, $q)
  . print_advance_write_pdb ($self, $q, 1)
  . print_advance_submit ($q);
  $msg .= "</table>\n";
  return $msg;
}


# generate advanced structure-sequence alignment form page
sub adv_stse
{
  my $self = shift;
  my $q = shift;
  my $job_name = shift;
  my $email = shift;
  my %params; # Fetch all form values from default view.
  foreach my $param_name ($q->param) {
     $params{$param_name} = $q->param($param_name);
  }
  my $upld_pseqs = $params{'upld_pseqs'};
  
  my $msg = print_cont1_advance_option ($self, $q);
  $msg .= $q->start_multipart_form( -method => "post", -action => $self->submit_url ).
 	$q->hidden( -name => "tool", -default => "str_seq_adv", -override => 1).
        $q->hidden( -name => "job_name", -default => $job_name, -override => 1).
	$q->hidden( -name => "email", -default => $email, -override => 1).
	$q->hidden( -name => "upld_pseqs", -default => $upld_pseqs, -override => 1);

  $msg .= "<p>Depending on the choice of the alignment category, some options may have no effect.</p>\n";

  $msg .= "<table>\n"
  . print_advance_alignment_category_2 ($self, $q)
  . print_alignment_type ($self, $q)
  . print_advance_pdb_segments ($self, $q, \%params)
  . print_advance_uploaded_ali ($q, \%params)
  . print_advance_penalties_2a ($self, $q)
  . print_advance_weight ($self, $q)
  . print_advance_rms ($self, $q)
  . print_advance_gap ($self, $q, 1)
  . print_advance_fit ($self, $q)
  . print_advance_improve ($self, $q)
  . print_advance_write_pdb ($self, $q, 0)
  . print_advance_submit ($q)
  . "</table>\n";
  return $msg;
}
  

# generate advanced sequence-sequence alignment form page
sub adv_sese
{
  my $self = shift;
  my $q = shift;
  my $job_name = shift;
  my $email = shift;

  # Fetch all form values from default view.
  my %params;
  foreach my $param_name ($q->param) {
     $params{$param_name} = $q->param($param_name);
  }
  my $upld_pseqs = $params{'upld_pseqs'};
  my $structures = $params{'structures'};

  my $msg = print_cont1_advance_option ($self, $q);
  $msg .= $q->start_multipart_form( -method => "post", -action => $self->submit_url ).
 	$q->hidden( -name => "tool", -default => "sese_adv", -override => 1).
        $q->hidden( -name => "job_name", -default => $job_name, -override => 1).
	$q->hidden( -name => "email", -default => $email, -override => 1).
	$q->hidden( -name => "upld_pseqs", -default => $upld_pseqs, -override => 1).
	$q->hidden( -name => "structures", -default => $structures, -override => 1);

  if ( $params{'caller'} eq '2s_sese' ) {
     $msg .= "<p>Depending on the choice of the alignment category, some options may have no effect.</p>\n";
  }

  $msg .= "<table>\n";
  if ( $params{'caller'} eq '2s_sese' ) {
     $msg .= print_advance_alignment_category_3 ($self, $q, $structures); 

     if ( $structures == 1 ) {
  	$msg .= print_advance_pdb_segments ($self, $q, \%params); 
     }
  }  
  else #called from 1step seq seq
  {
     $msg .= $q->hidden( -name => "sa_feature", -default => "1s_sese", -override => 1 );
  }

  # Present uploaded ali files and no of pasted seqs
  $msg .= print_advance_uploaded_ali ($q, \%params)
          . print_alignment_type ($self, $q);

  if ( $structures == 1 ) {
     $msg .= print_advance_penalties_2b ($self, $q)
     . print_advance_weight ($self, $q)
     . print_advance_rms ($self, $q)
     . print_advance_gap ($self, $q, 1)
     . print_advance_fit ($self, $q)
     . print_advance_write_pdb ($self, $q, 1);
  }
  else {
     $msg .= print_advance_penalties_3 ($self, $q)
             . print_advance_gap ($self, $q, 0);
  }
  $msg .= print_advance_improve ($self, $q) . print_advance_submit ($q)
          . "</table>\n";
  return $msg;
}
  
sub make_size_nice
{
  my $filesize = shift;
  my $size;
  if ($filesize > 500000) {
     $size=$filesize/1048576;
     $size=sprintf "%.2f",$size;
     $size=$size." MB"; } 
  elsif ($filesize > 500) {
     $size=$filesize/1024;
     $size=sprintf "%.2f",$size;
     $size=$size." KB"; } 
  else {
     $size=$filesize;
     $size=sprintf "%.2f",$size;
     $size=$size." B"; }
  return ($size);
}

sub print_cont1_category_choice {
	my ($self, $q, $cat_choice) = @_;

return $q->h2("<br />Choice of alignment category",  $self->help_link("ali_cat_choice"),
	     ": &nbsp;$cat_choice", $q->br, $q->hr);
}

sub print_cont1_advance_option {
	my ($self, $q) = @_;

return $q->h2("<br />SALIGN Advanced Options",  help_link_2($q, ""), $q->br, $q->hr);
}

sub print_alignment_type {
  my ($self, $q) = @_;

  return	$q->Tr($q->td("Alignment type", help_link_2($q, "ali_type"), $q->br),
		$q->td($q->radio_group(
	  			-name    => "align_type",
				-values  => [ "progressive","tree","automatic" ],
	 			-default => "automatic",
				-labels  => { "automatic"   => "",
	             			      "progressive" => "Progressive ",
					      "tree"        => "Tree "          }
			), "Optimal", $self->help_link("ali_type"), $q->br, $q->br));
}

sub print_advance_alignment_category {
  my ($self, $q) = @_;

  return	$q->Tr($q->td("Alignment category", $self->help_link("ali_cat"), $q->br, $q->br),
	$q->td($q->popup_menu(
	  -name    => "sa_feature",
	  -values  => [ "str_str", "1s_sese" ],
	  -default => "str_str",
	  -labels  => { "str_str" => "Structure-structure alignment",
			"1s_sese" => "Sequence-sequence alignment"    }
	)));
}
sub print_advance_alignment_category_2 {
  my ($self, $q) = @_;

  return	$q->Tr($q->td("Alignment category", $self->help_link("ali_cat"), $q->br, $q->br),
	$q->td($q->popup_menu(
	  -name    => "sa_feature",
	  -values  => [ "str_seq", "1s_sese" ],
	  -default => "str_seq",
	  -labels  => { "str_seq" => "Structure-sequence alignment",
			"1s_sese" => "Sequence-sequence alignment"    }
	)));
}

sub print_advance_alignment_category_3 {
  my ($self, $q, $structures) = @_;

  if ($structures == 1){
    return $q->Tr($q->td("Alignment category", $self->help_link("ali_cat"), $q->br, $q->br),
		$q->td($q->popup_menu(
		-name    => "sa_feature",
                -values  => [ "2s_sese","str_seq","1s_sese" ],
		-default => "2s_sese",
		-labels  => { "2s_sese" => "Two step sequence-sequence alignment",
                              "str_seq" => "Structure-sequence alignment",
		              "1s_sese" => "One step sequence-sequence alignment"  }
		)));
  } else{
    return $q->Tr($q->td("Alignment category", $self->help_link("ali_cat"), $q->br, $q->br),
		$q->td($q->popup_menu(
		-name    => "sa_feature",
                -values  => [ "2s_sese","1s_sese" ],
                -default => "2s_sese",
                -labels  => { "2s_sese" => "Two step sequence-sequence alignment",
		              "1s_sese" => "One step sequence-sequence alignment"  }
		)));
  }
}

sub print_advance_penalties {
  my ($self, $q) = @_;

  return $q->Tr($q->td("1D gap penalties", $self->help_link("1D_gap_pen"), $q->br),
		$q->td($q->i("Opening: "),
		$q->textfield( -name => "1D_open_usr", -default => "Default", -size => "10" ),
		$q->i("&nbsp Extension: "),
		$q->textfield( -name => "1D_elong_usr", -default => "Default", -size => "10" ),
  		$q->hidden( -name => "1D_open_stst", -default => "-150", -override => 1 ),
		$q->hidden( -name => "1D_elong_stst", -default => "-50", -override => 1 ),
		$q->hidden( -name => "1D_open_sese", -default => "-450", -override => 1),
		$q->hidden( -name => "1D_elong_sese", -default => "-50", -override => 1),
		$q->br)).

        $q->Tr($q->td("3D gap penalties", help_link_2($q, "3D_gap_pen"), $q->br),
		$q->td($q->i("Opening: "),
		$q->textfield( -name => "3D_open", -default => "0", -size => "10" ),
		$q->i("&nbsp Extension: "),
		$q->textfield( -name => "3D_elong", -default => "2", -size => "10" )),
		$q->hidden( -name => "fw_1", -default => "1", -override => 1 ),
		$q->hidden( -name => "fw_2", -default => "1", -override => 1 ),
		$q->hidden( -name => "fw_3", -default => "1", -override => 1 ),
		$q->hidden( -name => "fw_4", -default => "1", -override => 1 ),
		$q->hidden( -name => "fw_5", -default => "1", -override => 1 ),
		$q->hidden( -name => "fw_6", -default => "0", -override => 1 ),
		$q->br, $q->br).
        $q->Tr($q->td("&nbsp;"));
}


sub print_advance_penalties_3 {
  my ($self, $q) = @_;

  return	$q->Tr($q->td("1D gap penalties", $self->help_link("1D_gap_pen"), $q->br),
		$q->td($q->i("Opening: "),
		$q->textfield( -name => "1D_open_usr", -default => "Default", -size => "10" ),
		$q->i("&nbsp Extension: "),
		$q->textfield( -name => "1D_elong_usr", -default => "Default", -size => "10" ),
		$q->hidden( -name => "1D_open_sese", -default => "-450", -override => 1 ),
		$q->hidden( -name => "1D_elong_sese", -default => "-50", -override => 1 ),
		$q->hidden( -name => "1D_open_prof", -default => "-300", -override => 1),
		$q->hidden( -name => "1D_elong_prof", -default => "0", -override => 1),
		$q->br, $q->br));
}

sub print_advance_penalties_2a {
  my ($self, $q) = @_;

  return print_advance_penalties_2 ($q) .
        $q->Tr($q->td("3D gap penalties", help_link_2($q, "3D_gap_pen"), $q->br),
		$q->td($q->i("Opening: "),
		$q->textfield( -name => "3D_open", -default => "0", -size => "10" ),
		$q->i("&nbsp Extension: "),
		$q->textfield( -name => "3D_elong", -default => "2", -size => "10" )),
		$q->hidden( -name => "fw_1", -default => "1", -override => 1 ),
		$q->hidden( -name => "fw_2", -default => "1", -override => 1 ),
		$q->hidden( -name => "fw_3", -default => "1", -override => 1 ),
		$q->hidden( -name => "fw_4", -default => "1", -override => 1 ),
		$q->hidden( -name => "fw_5", -default => "1", -override => 1 ),
		$q->hidden( -name => "fw_6", -default => "0", -override => 1 ),
		$q->br, $q->br) .
        $q->Tr($q->td("&nbsp;"));
}

sub print_advance_penalties_2b {
  my ($self, $q) = @_;

  return print_advance_penalties_2 ($self, $q).
        $q->Tr($q->td("3D gap penalties", help_link_2($q, "3D_gap_pen"), $q->br),
		$q->td($q->i("Opening: "),
		$q->textfield( -name => "3D_open", -default => "0", -size => "10" ),
		$q->i("&nbsp Extension: "),
		$q->textfield( -name => "3D_elong", -default => "2", -size => "10" )),
		$q->hidden( -name => "fw_1", -default => "0", -override => 1 ),
		$q->hidden( -name => "fw_2", -default => "1", -override => 1 ),
		$q->hidden( -name => "fw_3", -default => "0", -override => 1 ),
		$q->hidden( -name => "fw_4", -default => "0", -override => 1 ),
		$q->hidden( -name => "fw_5", -default => "0", -override => 1 ),
		$q->hidden( -name => "fw_6", -default => "0", -override => 1 ),
		$q->br, $q->br).
         $q->Tr($q->td("&nbsp;"));
}

sub print_advance_penalties_2 {
  my ($self, $q) = @_;

  return	$q->Tr($q->td("1D gap penalties", $self->help_link("1D_gap_pen"), $q->br),
		$q->td($q->i("Opening: "),
		$q->textfield( -name => "1D_open_usr", -default => "Default", -size => "10" ),
		$q->i("&nbsp Extension: "),
		$q->textfield( -name => "1D_elong_usr", -default => "Default", -size => "10" ),
  		$q->hidden( -name => "1D_open_stst", -default => "-150", -override => 1 ),
		$q->hidden( -name => "1D_elong_stst", -default => "-50", -override => 1 ),
	        $q->hidden( -name => "1D_open_stse", -default => "-100", -override => 1),
		$q->hidden( -name => "1D_elong_stse", -default => "0", -override => 1),
		$q->hidden( -name => "1D_open_sese", -default => "-450", -override => 1),
		$q->hidden( -name => "1D_elong_sese", -default => "-50", -override => 1),
		$q->hidden( -name => "1D_open_prof", -default => "-300", -override => 1),
		$q->hidden( -name => "1D_elong_prof", -default => "0", -override => 1),
		$q->br, $q->br)).
  	$q->Tr($q->td("<br />2D gap penalties", help_link_2($q, "2D_gap_pen"), $q->br),
		$q->td(
		$q->table($q->Tr(
		$q->td($q->i("Helicity: "),
		$q->td($q->textfield( -name => "2D_1", -default => "3.5", -size => "5" ),
		$q->br))), $q->Tr(
		$q->td($q->i("Strandedness: "),
		$q->td($q->textfield( -name => "2D_2", -default => "3.5", -size => "5" ),
		$q->br))), $q->Tr(
		$q->td($q->i("Burial:"),
		$q->td($q->textfield( -name => "2D_3", -default => "3.5", -size => "5" ),
		$q->br))), $q->Tr(
		$q->td($q->i("Local straightness: "), 
		$q->td($q->textfield( -name => "2D_4", -default => "0.2", -size => "5" ),
		$q->br))), $q->Tr(
		$q->td($q->i("Gap spanning distance: "),
		$q->td($q->textfield( -name => "2D_5", -default => "4.0", -size => "5" ),
		$q->br))), $q->Tr(
  		$q->td($q->i("Optimal gap distance: "),
		$q->td($q->textfield( -name => "2D_6", -default => "6.5", -size => "5" ),
		$q->br))), $q->Tr(
		$q->td($q->i("Exponent of gap spanning distance: "),
		$q->td($q->textfield( -name => "2D_7", -default => "2.0", -size => "5" ),
		$q->br))), $q->Tr(
		$q->td($q->i("Diagonal gap penalty: "),
		$q->td($q->textfield( -name => "2D_8", -default => "0.0", -size => "5" ),
		$q->hidden( -name => "2D_9", -default => "0", -override => 1 ),
		$q->br, $q->br))))));

}

sub print_advance_weight {
  my ($self, $q) = @_;

  return	$q->Tr($q->td("External weight matrix", help_link_2($q, "wt_mtx"), $q->br),
		$q->td($q->filefield( -name => "weight_mtx" ), $q->br, $q->br));

#	$q->a({-href=>'/salign/manual.html#feat_wts'}, "Feature weights"), $q->br, $q->br,
#	$q->i("Feature 1: "), $q->textfield( -name => "fw_1", -default => "1",   -size => "5" ),
#	$q->i("&nbsp Feature 2: "), $q->textfield( -name => "fw_2", -default => "1",   -size => "5" ),
#	$q->i("&nbsp Feature 3: "), $q->textfield( -name => "fw_3", -default => "1",   -size => "5" ),	$q->br,
#	$q->i("Feature 4: "),$q->textfield( -name => "fw_4", -default => "1",   -size => "5" ),
#	$q->i("&nbsp Feature 5: "), $q->textfield( -name => "fw_5", -default => "1",   -size => "5" ),
#	$q->i("&nbsp Feature 6: "), $q->textfield( -name => "fw_6", -default => "0",   -size => "5" ),
}

sub print_advance_rms {
  my ($self, $q) = @_;

  return	$q->Tr($q->td("RMS cut-off for average number<br /> of equivalent positions determination",
		help_link_2($q, "rms_cutoff"), $q->br),
		$q->td($q->textfield( -name => "RMS_cutoff", -default => "3.5", -size => "5"),
		$q->br, $q->br));
}

sub print_advance_gap {
  my ($self, $q, $max_gap) = @_;

  my $msg = '';
  if ($max_gap == 1){
      $msg .=	$q->Tr($q->td("Max gap length", help_link_2($q, "max_gap"), $q->br),
		$q->td($q->textfield( -name => "max_gap", -default => "20", -size => "5"),
		$q->br, $q->br));
  }

  $msg .=	$q->Tr($q->td("Overhangs", help_link_2($q, "overhang"), $q->br),
		$q->td($q->textfield( -name => "overhangs", -default => "0", -size => "5"),
		$q->br, $q->br));

  $msg .=	$q->Tr($q->td("Gap-gap score", help_link_2($q, "gap_gap_score"), $q->br),
		$q->td($q->textfield( -name => "gap-gap_score", -default => "0", -size => "5"),
		$q->br, $q->br));

  $msg .=	$q->Tr($q->td("Gap-gap residue", help_link_2($q, "gap_res_score"), $q->br),
		$q->td($q->textfield( -name => "gap-res_score", -default => "0", -size => "5"),
		$q->br, $q->br));
  return $msg;
}

sub print_advance_fit {
  my ($self, $q) = @_;

  return	$q->Tr($q->td("Fit", help_link_2($q, "fit"), $q->br),
		$q->td($q->radio_group(
		  		-name    => "fit",
		 		-values  => [ "True", "False" ],
		  		-default => "True",
		 		-labels  => { "True" => "True ",
					     "False" => "False" }
			), $q->br, $q->br));
}

sub print_advance_improve {
  my ($self, $q) = @_;

  return	$q->Tr($q->td("Improve alignment", help_link_2($q, "improve"), $q->br),
		$q->td($q->radio_group(
				  -name    => "improve",
				  -values  => [ "True", "False" ],
				  -default => "True",
				  -labels  => { "True" => "True ",
	              			       "False" => "False" }
			), $q->br, $q->br));
}

sub print_advance_write_pdb {
  my ($self, $q, $show) = @_;

  if ($show == 1) {
      return	$q->Tr($q->td("Write whole PDB", help_link_2($q, "write_whole"), $q->br),
		$q->td($q->radio_group(
				  -name    => "write_whole",
				  -values  => [ "True", "False" ],
				  -default => "False",
				  -labels  => { "True" => "True ",
	               		 	       "False" => "False" }
			), $q->br, $q->br));
  }
  else {
      return $q->hidden( -name => "write_whole", -default => "False", -override => 1 ),
  }
}

sub print_advance_submit {
  my $q = shift;

  return	$q->Tr($q->td({-colspan=>"2"},
                      $q->input({-type=>"submit", -value=>"Submit"}) .
                      $q->input({-type=>"reset", -value=>"Reset"}) .
                             "<p>&nbsp;</p>") .
        $q->end_form);
}




sub print_advance_pdb_segments {
   my ($self, $q, $params_ref) = @_;
   my %params = %$params_ref;

   my $msg = '';
   $msg .= "<tr>";
   $msg .= $q->td("Specify PDB segments", $self->help_link("segments"), $q->br);
   $msg .= "<td>";

  # Retrieve structures and their default segments sent from simple view
  my %segments;
  foreach my $param_name ( keys %params )
  {
     my $str_name = $param_name;
     # Segments from uploaded files
     if ( $str_name =~ s/^uplsegm_// )
     {
	$segments{'upl'}{$str_name} = $params{$param_name};
     }
     # Segments from library files
     elsif ( $str_name =~ s/^libsegm_// )
     {
	$segments{'lib'}{$str_name} = $params{$param_name};
     }
  }
  if ( exists $segments{'upl'} )
  {
     $msg .= $q->p("Uploaded structure files");
     foreach my $str_name ( keys %{ $segments{'upl'} } )
     {
        $msg .= $q->i("$str_name&nbsp").
              $q->textarea( 
	        -name => "uplsegm_$str_name", 
	        -cols => "15", 
	        -rows => "2", 
	        -default => $segments{'upl'}{$str_name},
		-override => 1
	      ).
	      $q->br;
     }
  }
  if ( exists $segments{'lib'} )
  {
     $msg .= $q->p("Structures from SALIGN PDB library");
     foreach my $str_name ( keys %{ $segments{'lib'} } )
     {
        $msg .= $q->i("$str_name&nbsp").
              $q->textarea( 
	        -name => "libsegm_$str_name", 
	        -cols => "15", 
	        -rows => "2", 
	        -default => $segments{'lib'}{$str_name},
		-override => 1
	      ).
	      $q->br;
     }
  }
  $msg .= "<br /></td></tr>";
  return $msg;
}

sub print_advance_uploaded_ali {
  my ($q, $params_ref) = @_;

  my %params = %$params_ref; 
  my $upld_pseqs = $params{'upld_pseqs'};
  my $msg = "<tr><td>&nbsp;</td><td>";

  # Present uploaded ali files and no of pasted seqs
  unless ( $params{'ali_files'} eq '' ) {
     $msg .= $q->p("Uploaded alignment files");
     my @ali_files = split ( " ",$params{'ali_files'} );
     foreach my $filen ( @ali_files ) {
        $msg .= $q->p( $filen );
     }
  }
  if ($upld_pseqs > 0) {
     if ($upld_pseqs == 1) {
	$msg .= $q->p("$upld_pseqs pasted sequence uploaded");
     }
     else {
	$msg .= $q->p("$upld_pseqs pasted sequences uploaded");
     }
  }
  $msg .= "<br /></td></tr>";
  return $msg;
}

sub print_pdb_segments {
   my ($self, $q, $upl_files_ref, $lib_PDBs_ref) = @_;
   my %upl_files = %$upl_files_ref;
   my %lib_PDBs = %$lib_PDBs_ref;

   my $msg = "<tr>";
   $msg .=  $q->td("Specify PDB segments\n", $self->help_link("segments"), $q->br);
   $msg .= "<td>\n";


# Have user specify segments to use from uploaded files	and library PDBs
# Defaults are taken from ali file if corresponding entry exists.
# If not, default is FIRST:@:LAST:@  @ is wild card char and matches any chain
  if ( exists $upl_files{'str'} || exists $upl_files{'used_str'} )
  {
     $msg .= $q->p("Uploaded structure files");
     $msg .= "<table>\n";
     if ( exists $upl_files{'str'} )
     {	
        foreach my $filen ( keys %{ $upl_files{'str'} } )
        {
           $msg .= $q->Tr($q->td({-align=>"right"},$q->br,$q->i("$filen&nbsp")),
                 $q->td($q->textarea( 
	           -name => "uplsegm_$filen", 
	           -cols => "15", 
	           -rows => "2", 
		   -default => 'FIRST:@:LAST:@',
		   -override => 1
	         ),
	         $q->br));
        }
     }
     if ( exists $upl_files{'used_str'} )
     {
        foreach my $filen ( keys %{ $upl_files{'used_str'} } )
        {
	   # Get default segments
           my $default = join "\n", @{ $upl_files{'used_str'}{$filen} };
           $msg .= $q->Tr($q->td({-align=>"right"},$q->br,$q->i("$filen&nbsp"),
                 $q->td($q->textarea( 
	           -name => "uplsegm_$filen", 
	           -cols => "15", 
	           -rows => "2", 
		   -default => $default,
		   -override => 1
	         ),
	         $q->br)));
        }
     }
     $msg .= "</table>\n";
  }   
  if ( exists $lib_PDBs{'man'} || exists $lib_PDBs{'ali'} )
  { 
     $msg .= $q->p("Structures from SALIGN PDB library");
     $msg .= "<table>\n";
     if ( exists $lib_PDBs{'man'} )
     {
        foreach my $pdb ( keys %{ $lib_PDBs{'man'} } )
        {
	   # skip if same pdb exists in ali file entry
	   if ( exists $lib_PDBs{'ali'} )
	   {
	      if ( exists $lib_PDBs{'ali'}{$pdb} ) { next; }
           }
	   $msg .= $q->Tr($q->td({-align=>"right"},$q->br, $q->i("$pdb&nbsp")),
                 $q->td($q->textarea( 
                   -name => "libsegm_$pdb", 
                   -cols => "15", 
                   -rows => "2", 
		   -default => 'FIRST:@:LAST:@',
		   -override => 1
                 ),
                 $q->br));
        }
     }
     if ( exists $lib_PDBs{'ali'} )
     {
        foreach my $pdb ( keys %{ $lib_PDBs{'ali'} } )
        {
	   # Get default segments
           my $default = join "\n", @{ $lib_PDBs{'ali'}{$pdb} };
           $msg .= $q->Tr($q->td({-align=>"right"},$q->br,$q->i("$pdb&nbsp")),
                 $q->td($q->textarea( 
	           -name => "libsegm_$pdb",
	           -cols => "15", 
	           -rows => "2", 
		   -default => $default,
		   -override => 1
	         ),
	         $q->br));
        }
     }
     $msg .= "</table>\n";
  }
  $msg .= "</td></tr>\n";
  return $msg;
}

sub print_body1a_intro {
    my ($self, $q) = @_;
    my $ind = $self->index_url;
	return <<BODY1a;
        <div id="resulttable">
		<h2 align="left">SALIGN: A multiple protein sequence/structure alignment server.</h2>
		<form method="post" action="$ind" enctype="multipart/form-data">
	<table>
		<tr><td colspan="2"><p>
				SALIGN is a general alignment module of the modeling program 
				<a href="http://salilab.org/modeller" target="_blank">MODELLER</a>.
				The alignments are computed using dynamic programming, making use of several features of the protein sequences and structures.
				SALIGN benchmarks from published papers are 
				<a href="http://salilab.org/projects/salign/" target="_blank">also available</a>.
				<br /><br />
		</p></td></tr>
BODY1a
}

sub print_body2_general_information {
    my ($self, $q, $email) = @_;
    my $help = $self->help_link("email");
    return <<BODY2;
		<tr><td><h4>General information</h4></td></tr>
		<tr>
			<td>Email address (optional) $help <br /></td>
			<td><input type="text" name="email" value="$email" size="25" /></td>
		</tr>
BODY2
}

sub print_body3_input_alignment {
	return <<BODY3;
		<tr>
			<td colspan="2"><h4>Input alignment information</h4>
			Users can either upload their own sequences/structures to align or choose structures from the PDB.<br /><br />
		</td></tr>
BODY3
}

sub print_body3a_sequence {
    my ($self, $upld_pseqs) = @_;
    my $help1 = $self->help_link("paste_seq");
    my $help2 = $self->help_link("seq_upload_button");
    return <<BODY3a;
		<tr>
			<td>Paste one sequence at a time, without header 
				$help1 <br /></td>

			<td>	<textarea name="paste_seq" rows="5" cols="40"></textarea><br />
					<input type="submit" name="state" value="Upload" />
					$help2
					<br /><br /><hr /></td>
		</tr>
BODY3a
}

sub print_body3b_file {
    my ($self, $q) = @_;
    my $help1 = $self->help_link("file_upload");
    my $help2 = $self->help_link("file_format");
    my $help3 = $self->help_link("file_upload_button");
    return <<BODY3b;
		<tr>
			<td>Upload sequence/PDB file(s) 
				$help1 <br />
			</td>

			<td>
				$help2
				<input type="file" name="upl_file" /> <br /><br />
				<input type="submit" name="state" value="Upload" />
				$help3
			<br /><br /><br /><hr />
			</td>
		</tr>
BODY3b
}

sub print_body3c_PDB_code {
    my ($self, $q) = @_;
    my $help = $self->help_link("lib_PDBs");
	return <<BODY3c;
		<tr>
			<td>Enter 4-letter code(s) to choose PDB structures 
				$help <br /></td>
			<td><textarea name="pdb_id" rows="5" cols="5"></textarea></td>
		</tr>
</table>
BODY3c
}
sub print_body3d_continue {
	my ($q, $job, $upld_pseqs) = @_;
        my $jobname = "";
	if ($job) {
            $jobname = '<input type="hidden" name="job_name" value="' .
                       $job->name . '" />';
        }
	return <<BODY3d;
<table>
	<tr>
		<td colspan="2">
			&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
			<input type="submit" name="state" value="Continue" />&nbsp;&nbsp;
			<input type="reset" value="Reset" />
		</td>
	</tr>
</table>
<div>
	$jobname
        <input type="hidden" name="upld_pseqs" value="$upld_pseqs" />
</div>
</form>
</div>
BODY3d
}

sub help_link_2 {
    my ($q, $target) = @_;
    my $url="/salign/html/manual.html#$target";
    return $q->a({-href=>"$url",
                  -class=>"helplink",
                  -onClick=>"launchHelp(\'$url\'); return false;"},
                 $q->img({-src=>"/saliweb/img/help.jpg", -alt=>"help",
                          -class=>"helplink"} ));
}

1;
