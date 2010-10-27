package salign;
use base qw(saliweb::frontend);
use strict;

use constant MAX_POST_SIZE => 1073741824; # 1GB maximum upload size
use salign::Utils;
use salign::CGI_Utils;
use Cwd;
use Fcntl qw( :DEFAULT :flock);
use DB_File;

# Enable users to upload files to our server
$CGI::DISABLE_UPLOADS = 0;

# Users not allowed to post more data than 1 MB 
$CGI::POST_MAX = MAX_POST_SIZE;

sub new {
    return saliweb::frontend::new(@_, @CONFIG@);
}

sub get_navigation_links {
    my $self = shift;
    my $q = $self->cgi;
    return [
        $q->a({-href=>$self->index_url}, "SALIGN Home"),
        $q->a({-href=>$self->queue_url}, "SALIGN Current queue"),
        $q->a({-href=>$self->help_url}, "SALIGN Help"),
        $q->a({-href=>$self->contact_url}, "SALIGN Contact")
        ];
}

sub get_project_menu {
    my $self = shift;
    my $version = $self->version;
    return <<MENU;
<p>&nbsp;</p>
<p>&nbsp;</p>
<p>&nbsp;</p>
<h4><small>Developers:</small></h4>
<p>
Hannes Braberg<br />
Mallur S. Madhusudhan<br />
Ursula Pieper<br />
Ben Webb<br />
Andrej Sali</p>
<p><i>Version $version</i></p>
MENU
}

sub get_footer {
    my $self = shift;
    my $htmlroot = $self->htmlroot;
    return <<FOOTER;
<div id="address">
<p>Please cite: Hannes Braberg, Mallur S. Madhusudhan, Ursula Pieper,
Ben Webb, Andrej Sali. SALIGN : A multiple protein structure/sequence
alignment web server. In preparation.</p>
</div>
FOOTER
}

sub get_index_page {
    my $self = shift;
    my $q = $self->cgi;

    my $job_name = $q->param('job_name') || '';
    my $cur_state = $q->param('state') || 'home';
    my $upld_pseqs = $q->param('upld_pseqs') || 0;
    my $email = $q->param('email') || "";
    my $pdb_id = $q->param('pdb_id') || "";

    # start requested option
    if ($cur_state eq "home") {
        return $self->home($q,$job_name,$upld_pseqs,$email,$pdb_id);
    } elsif ($cur_state eq "Upload") {
        return $self->upload_main($q,$job_name,$upld_pseqs,$email,$pdb_id);
    } elsif ($cur_state eq "Continue") {
        return $self->customizer($q,$job_name,$upld_pseqs,$email,$pdb_id);
    } elsif ($cur_state eq "Advanced") {
        my $caller = $q->param('caller');
        if ($caller eq 'str-str') {
            return adv_stst($q,$job_name,$email);
        } elsif ($caller eq 'str-seq') {
            return adv_stse($q,$job_name,$email);
        } elsif ($caller eq '2s_sese' || $caller eq '1s_sese') {
            return adv_sese($q,$job_name,$email);
        } else {
            throw saliweb::frontend::InternalError(
                              "Invalid advanced view option");
        }
    } else {
        throw saliweb::frontend::InternalError(
                          "Invalid routine");
    }
}

# Generate front page of salign interface
# Note that reset will only work first time since defaults change
sub home {
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

  my $page =
        $q->p("SALIGN is a general alignment module of the modeling program <a href=http://salilab.org/modeller>MODELLER</a>").
        $q->p("The alignments are computed using dynamic programming, making use of several features of the protein sequences and structures").
        $q->hr.
        $q->b("Users can either upload their own sequences/structures to align or choose structures from the PDB").
        $q->br.
        $q->p("sequences can either be pasted or uploaded as FASTA or PIR format alignment files").
        $q->start_multipart_form( -method => "post" ).
        $q->hidden( -name => "job_name", -default => $job_name,
          -override => 1).
        $q->hidden( -name => "upld_pseqs", -default => $upld_pseqs,
          -override => 1).
        $q->a({-href=>'/salign/salign_help.html#paste_seq'}, "Paste sequence to align").
        $q->p("Multiple sequences can be pasted by iteratively clicking 'upload' after every pasted sequence").
        $q->p("<i>Please paste one sequence at a time, without header</i>").
        $q->textarea(
          -name => "paste_seq",
          -cols => "60",
          -rows => "5",
          -default => "",
          -override => 1
        ).
        $q->br.$q->br.
        $q->a({-href=>'/salign/salign_help.html#file_upload'}, "Specify file to upload (PIR, FASTA, PDB, .zip or .tar.gz)").
        $q->p("Multiple files can be uploaded by iteratively clicking 'upload' after every file uploaded").
        $q->filefield( -name => "upl_file" ).
        $q->br.$q->br.
        $q->submit( -name => "state",
          -value => "Upload" ).
        $q->hr.
        $q->p("Uploaded files:");

  if ($job) {
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
           die("Job directory $job_name non existent");
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
        $page .= $q->p("No files uploaded");
     }
     else
     {
        foreach my $i ( 0 .. $#file_names )
        {
           my $nice_size = make_size_nice($file_sizes[$i]);
           $page .= $q->p("$file_names[$i],  $nice_size,  $file_times[$i]");
        }
     }
  } else {
    $page .= $q->p("No files uploaded");
  }

  if ($upld_pseqs > 0)
  {
     if ($upld_pseqs == 1)
     {
        $page .= $q->hr,
                 $q->p("$upld_pseqs pasted sequence uploaded");
     }
     else
     {
        $page .= $q->hr,
                 $q->p("$upld_pseqs pasted sequences uploaded");
     }
  }

  $page .= $q->hr.$q->br.
        $q->a({-href=>'/salign/salign_help.html#lib_PDBs'}, "Enter 4 letter code(s) to choose PDB structures").
        $q->br.$q->br.
        $q->textarea(
          -name => "pdb_id",
          -cols => "5",
          -rows => "5",
          -default => $pdb_id,
          -override => 1
        ).
        $q->br.$q->br.
        $q->a({-href=>'/salign/salign_help.html#email'}, "e-mail address, to receive results:").
        $q->br.$q->br.
        $q->textfield(
          -name => "email",
          -size => "20",
          -default => $email,
          -override => 1
        ).
        $q->br. $q->br.
        $q->submit( -name => "state", -value => "Continue" ).
        $q->reset().
        $q->end_form();

  return $page;
}

sub get_submit_page {
    # TODO
}

sub get_results_page {
    # TODO
}

sub get_job_object {
  my ($self, $job_name) = @_;
  my $job;
  if ($job_name) {
    $job = $self->resume_job($job_name);
  } else {
    $job = $self->make_job("job");
    $job_name = $job->name;
    mkdir $job->directory . "/upload"
      or die "Can't create sub directory " . $job->directory . "/upload: $!\n";
  }
  return $job;
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
# my $max_dir_size = $conf_ref->{'MAX_DIR_SIZE'};
  my $max_dir_size = 1073741824; # TODO
  my $buffer_size = 1024; # TODO

  my $job = $self->get_job_object($job_name);

  # Run sub check_dir_size to see that there is space for the request
  check_dir_size($q,$job->directory,$max_dir_size);
  
  # Check what is being uploaded
  my $upl_file = $q->param('upl_file'); 
  my $paste_seq = $q->param('paste_seq'); 
  if ( $upl_file eq "" && $paste_seq eq "" )
  {
     return $self->home($q,$job_name,$upld_pseqs,$email,$pdb_id);
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
        my $filen = file_upload($q,$upl_dir,$buffer_size,\%upldir_files,$upl_file);
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
     return $self->home($q,$job_name,$upld_pseqs,$email,$pdb_id);
  }
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
  # Read configuration file
# my $conf_file = '/modbase5/home/salign/conf/salign.conf';
# my $conf_ref = read_conf($conf_file);
# my $buffer_size = $conf_ref->{'BUFFER_SIZE'};
# my $max_dir_size = $conf_ref->{'MAX_DIR_SIZE'};
# my $max_open_tries = $conf_ref->{'MAX_OPEN_TRIES'};
# my $static_dir = $conf_ref->{'STATIC_DIR'};
  my $max_dir_size = 1073741824; # TODO
  my $buffer_size = 1024; # TODO
  my $static_dir = "/modbase5/home/salign/static"; # TODO

  my $job = $self->get_job_object($job_name);

  my $upl_dir = $job->directory . "/upload";
 
  # upload file if exists
  if ( $upl_file ne "" )
  {
     check_dir_size($q,$job->directory,$max_dir_size);
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
     my $filen = file_upload($q,$upl_dir,$buffer_size,\%upldir_files,$upl_file);
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
     if ( $upl_file eq "" ) { check_dir_size($q,$job->directory,$max_dir_size); }
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
     chk_alistrs(\%upl_files,$static_dir,\%upl_count,$job->directory,\%lib_PDBs,$upl_dir);
     %upl_files = %$upl_files_ref;
     %upl_count = %$upl_count_ref;
     %lib_PDBs  = %$lib_PDBs_ref;
  } 
  # guess what user wants
  my $choice = guess(\%upl_files,\%lib_PDBs,$upld_pseqs,\%upl_count);

  if ( $choice eq 'str-str' )
  {
     return $self->str_str($q,$email,\%upl_files,\%lib_PDBs,$job_name);
  }
  elsif ( $choice eq 'str-seq' )
  {
     return $self->str_seq($q,$email,\%upl_files,\%lib_PDBs,$upld_pseqs,$job_name);
  }
  elsif ( $choice eq '2s_seq-seq' )
  {
     return $self->twostep_sese($q,$email,\%upl_files,$upld_pseqs,$job_name,\%lib_PDBs);
  }
  elsif ( $choice eq '1s_seq-seq' )
  {
     return $self->onestep_sese($q,$email,\%upl_files,$upld_pseqs,$job_name);
  }
}

	
# upload files
sub file_upload
{
  my $q = shift;
  my $upl_dir = shift;
  my $buffer_size = shift;
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
  while( read($fh,$buffer,$buffer_size) ) {print UPLOAD_OUT "$buffer";}

  close UPLOAD_OUT;
  chmod(oct(666),"$upl_dir/$filen") or die "Can't change input_file mode: $!\n";
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

  if ( $new == 1 )
  {
     chmod(oct(666),"$job_dir/$filen") 
       or die "Can't change pasted_seqs mode: $!\n";
  }
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
  else {error($q,"Can't untaint run directory");}
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
     error($q,"Uploaded file $cmp_file not supported file type");
     #add line that moves all of this to rejected dir
  }

  # create directory for unzipping if it doesn't exist
  unless ( -d $unzip_dir )
  {
     mkdir $unzip_dir or die "Can't create sub directory $unzip_dir: $!\n";
     chmod(oct(777),$unzip_dir) or die "Can't change $unzip_dir mode: $!\n";
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
        error ($q,"gzip file content not a .tar file");
        #add line that moves all of this to rejected dir
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
     my $direc = dir_chk($unzip_dir,$filen);
     if ($direc == 1)
     {
#        rmdir("$unzip_dir/$filen")
#          or die "Could not remove directory in zip file: $!";
        next;
     }
     #check that file is ascii
     my $ascii = ascii_chk($unzip_dir,$filen);
     unless ($ascii == 1) 
     {
        error ($q,"Non ascii file found where only ascii files allowed: $filen");
     }	
     #skip if file with same name exists in $upl_dir
     if ( exists $xupldir_files{$filen} ) 
     { 
        push @redundant,$filen;
	next; 
     }
     chmod(oct(666),"$unzip_dir/$filen") or die "Can't change $filen mode: $!\n";
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
  if ( $pre_made == 0 )
  {
     chmod(oct(666),"$job_dir/upl_files.db") or die "Can't change filetype DBM mode: $!\n";
  }
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
     error ($q,"Not correct PDB, pir or fasta format");
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
  my $static_dir = shift;
  my $upl_count_ref = shift;
  my $job_dir = shift;
  my $lib_PDBs_ref = shift;
  my $upl_dir = shift;
  my %upl_files = %$upl_files_ref;
  my %upl_count = %$upl_count_ref;
  my %lib_PDBs = %$lib_PDBs_ref;
  
  my %changes;
  my $pdb_dbm = "$static_dir/lib_pdbs.db";
  tie my %pdb_hash, "DB_File", $pdb_dbm, O_RDONLY
    or die "Cannot open tie to PDB DBM: $!";
     
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
              if ( exists $pdb_hash{"pdb$pdb_code.ent"}  ||
#	           exists $pdb_hash{"pdb$pdb_code.pdb"}  || 
	           exists $pdb_hash{"pdb$pdb_code"}      || 
                   exists $pdb_hash{"$pdb_code.ent"}     ||
#	           exists $pdb_hash{"$pdb_code.pdb"}     || 
	           exists $pdb_hash{"$pdb_code"}             )
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
              if ( exists $pdb_hash{"pdb$pdb_code.ent"}  ||
#	           exists $pdb_hash{"pdb$pdb_code.pdb"}  || 
	           exists $pdb_hash{"pdb$pdb_code"}      || 
                   exists $pdb_hash{"$pdb_code.ent"}     ||
#	           exists $pdb_hash{"$pdb_code.pdb"}     || 
	           exists $pdb_hash{"$pdb_code"}             )
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
  untie %pdb_hash;
     
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
  
# Start html
  my $page = $q->a({-href=>'/salign/salign_help.html#ali_cat_choice'},"Choice of alignment category:").
        $q->b("&nbsp Structure-structure alignment").
        $q->p("Specified structure segments will be multiply aligned").
	$q->hr.
        $q->start_form( -method => "post", -action => "/salign-cgi/form_proc.cgi" ).
	$q->hidden( -name => "tool", -default => "str_str", 
	  -override => 1).
        $q->hidden( -name => "job_name", -default => $job_name,
          -override => 1).
	$q->hidden( -name => "email", -default => $email,
          -override => 1).
  	$q->a({-href=>'/salign/salign_help.html#segments'}, "Specify PDB segments");
# Have user specify segments to use from uploaded files	and library PDBs
# Defaults are taken from ali file if corresponding entry exists.
# If not, default is FIRST:@:LAST:@  @ is wild card char and matches any chain
  if ( exists $upl_files{'str'} || exists $upl_files{'used_str'} )
  {
     $page .= $q->p("Uploaded structure files");
     if ( exists $upl_files{'str'} )
     {
        foreach my $filen ( keys %{ $upl_files{'str'} } )
        {
           $page .= $q->i("$filen&nbsp").
                 $q->textarea( 
	           -name => "uplsegm_$filen", 
	           -cols => "15", 
	           -rows => "2", 
		   -default => 'FIRST:@:LAST:@',
		   -override => 1
	         ).
	         $q->br;
        }
     }
     if ( exists $upl_files{'used_str'} )
     {
        foreach my $filen ( keys %{ $upl_files{'used_str'} } )
        {
	   # Get default segments
           my $default = join "\n", @{ $upl_files{'used_str'}{$filen} };
           $page .= $q->i("$filen&nbsp").
                 $q->textarea( 
	           -name => "uplsegm_$filen", 
	           -cols => "15", 
	           -rows => "2", 
		   -default => $default,
		   -override => 1
	         ).
	         $q->br;
        }
     }
  }   
  if ( exists $lib_PDBs{'man'} || exists $lib_PDBs{'ali'} )
  { 
     $page .= $q->p("Structures from SALIGN PDB library");
     if ( exists $lib_PDBs{'man'} )
     {
        foreach my $pdb ( keys %{ $lib_PDBs{'man'} } )
        {
	   # skip if same pdb exists in ali file entry
	   if ( exists $lib_PDBs{'ali'} )
	   {
	      if ( exists $lib_PDBs{'ali'}{$pdb} ) { next; }
           }
	   $page .= $q->i("$pdb&nbsp").
                 $q->textarea( 
                   -name => "libsegm_$pdb", 
                   -cols => "15", 
                   -rows => "2", 
		   -default => 'FIRST:@:LAST:@',
		   -override => 1
                 ).
                 $q->br;
        }
     }
     if ( exists $lib_PDBs{'ali'} )
     {
        foreach my $pdb ( keys %{ $lib_PDBs{'ali'} } )
        {
	   # Get default segments
           my $default = join "\n", @{ $lib_PDBs{'ali'}{$pdb} };
           $page .= $q->i("$pdb&nbsp").
                 $q->textarea( 
	           -name => "libsegm_$pdb",
	           -cols => "15", 
	           -rows => "2", 
		   -default => $default,
		   -override => 1
	         ).
	         $q->br;
        }
     }
  }
#  # Show uploaded ali files - do we want this or not?
#  if ( exists $upl_files{'ali_st'} )
#  {
#     print $q->p("Uploaded structure alignment files");
#     foreach my $filen ( keys %{ $upl_files{'ali_st'} } )
#     {
#        print $q->p( $filen );
#     }   
#  }
  $page .= $q->hidden( -name => "align_type", -default => "automatic",
          -override => 1 ).
        $q->hidden( -name => "1D_open_stst", -default => "-150",
	  -override => 1 ).
	$q->hidden( -name => "1D_elong_stst", -default => "-50",
	  -override => 1 ).
	$q->hidden( -name => "3D_open", -default => "0",
	  -override => 1 ).
	$q->hidden( -name => "3D_elong", -default => "2",
	  -override => 1 ).
	$q->hidden( -name => "fw_1", -default => "1",
	  -override => 1 ).
	$q->hidden( -name => "fw_2", -default => "1",
	  -override => 1 ).
	$q->hidden( -name => "fw_3", -default => "1",
	  -override => 1 ).
	$q->hidden( -name => "fw_4", -default => "1",
	  -override => 1 ).
	$q->hidden( -name => "fw_5", -default => "1",
	  -override => 1 ).
	$q->hidden( -name => "fw_6", -default => "0",
	  -override => 1 ).
	$q->hidden( -name => "max_gap", -default => "20",
	  -override => 1 ).
	$q->hidden( -name => "RMS_cutoff", -default => "3.5",
	  -override => 1 ).
	$q->hidden( -name => "overhangs", -default => "0",
	  -override => 1 ).
	$q->hidden( -name => "fit", -default => "True",
	  -override => 1 ).
	$q->hidden( -name => "improve", -default => "True",
	  -override => 1 ).
	$q->hidden( -name => "write_whole", -default => "False",
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
  
  # form for call to advanced view
  $page .= $q->start_form( -method => "get" ).
        $q->hidden( -name => "caller", -default => "str-str",
	  -override => 1 ).
	$q->hidden( -name => "job_name", -default => $job_name,
          -override => 1).
	$q->hidden( -name => "email", -default => $email,
          -override => 1);
  if ( exists $upl_files{'str'} )
  {
     foreach my $filen ( keys %{ $upl_files{'str'} } )
     {
        $page .= $q->hidden( 
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
        $page .= $q->hidden( 
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
        $page .= $q->hidden(
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
        $page .= $q->hidden( 
	        -name => "libsegm_$pdb",
	        -default => $default,
	        -override => 1
	      );
     }
  }
  $page .= $q->submit( -name => "state", -value => "Advanced" ),
           $q->end_form();
  return $page;
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
  my $q = shift;
  my $email = shift;
  my $upl_files_ref = shift;
  my $lib_PDBs_ref = shift;
  my $upld_pseqs = shift;
  my $job_name = shift;
  my %upl_files = %$upl_files_ref;
  my %lib_PDBs = %$lib_PDBs_ref;
  
# Start html
  start($q);
  print	$q->a({-href=>'/salign/salign_help.html#ali_cat_choice'},"Choice of alignment category:"), 
        $q->b("&nbsp Structure-sequence alignment"),
        $q->p("Step 1: Structures and sequences will be multiply aligned independently"),
	$q->p("Step 2: The resulting alignments from step 1 will be aligned to each other"),
	$q->hr,
        $q->start_form( -method => "post", -action => "/salign-cgi/form_proc.cgi" ),
	$q->hidden( -name => "tool", -default => "str_seq", 
	  -override => 1),
        $q->hidden( -name => "job_name", -default => $job_name,
          -override => 1),
	$q->hidden( -name => "email", -default => $email,
          -override => 1),
	$q->hidden( -name => "upld_pseqs", -default => $upld_pseqs,
          -override => 1),
	$q->a({-href=>'/salign/salign_help.html#segments'}, "Specify PDB segments");
# Have user specify segments to use from uploaded files	and library PDBs
# Defaults are taken from ali file if corresponding entry exists.
# If not, default is FIRST:@:LAST:@  @ is wild card char and matches any chain
  if ( exists $upl_files{'str'} || exists $upl_files{'used_str'} )
  {
     print $q->p("Uploaded structure files");
     if ( exists $upl_files{'str'} )
     {
        foreach my $filen ( keys %{ $upl_files{'str'} } )
        {
           print $q->i("$filen&nbsp"),
                 $q->textarea( 
	           -name => "uplsegm_$filen", 
	           -cols => "15", 
	           -rows => "2", 
		   -default => 'FIRST:@:LAST:@',
		   -override => 1
	         ),
	         $q->br;
        }
     }
     if ( exists $upl_files{'used_str'} )
     {
        foreach my $filen ( keys %{ $upl_files{'used_str'} } )
        {
	   # Get default segments
           my $default = join "\n", @{ $upl_files{'used_str'}{$filen} };
           print $q->i("$filen&nbsp"),
                 $q->textarea( 
	           -name => "uplsegm_$filen", 
	           -cols => "15", 
	           -rows => "2", 
		   -default => $default,
		   -override => 1
	         ),
	         $q->br;
        }
     }
  }   
  if ( exists $lib_PDBs{'man'} || exists $lib_PDBs{'ali'} )
  { 
     print $q->p("Structures from SALIGN PDB library");
     if ( exists $lib_PDBs{'man'} )
     {
        foreach my $pdb ( keys %{ $lib_PDBs{'man'} } )
        {
	   # skip if same pdb exists in ali file entry
	   if ( exists $lib_PDBs{'ali'} )
	   {
	      if ( exists $lib_PDBs{'ali'}{$pdb} ) { next; }
           }
	   print $q->i("$pdb&nbsp"),
                 $q->textarea( 
                   -name => "libsegm_$pdb", 
                   -cols => "15", 
                   -rows => "2", 
		   -default => 'FIRST:@:LAST:@',
		   -override => 1
                 ),
                 $q->br;
        }
     }
     if ( exists $lib_PDBs{'ali'} )
     {
        foreach my $pdb ( keys %{ $lib_PDBs{'ali'} } )
        {
	   # Get default segments
           my $default = join "\n", @{ $lib_PDBs{'ali'}{$pdb} };
           print $q->i("$pdb&nbsp"),
                 $q->textarea( 
	           -name => "libsegm_$pdb",
	           -cols => "15", 
	           -rows => "2", 
		   -default => $default,
		   -override => 1
	         ),
	         $q->br;
        }
     }
  }
  # Show uploaded ali files and no of pasted seqs
  if ( exists $upl_files{'ali_st'} || exists $upl_files{'ali_stse'} ||
       exists $upl_files{'ali_seq'} )
  {
     print $q->p("Uploaded alignment files");
     my @ali_cats = qw( ali_st ali_stse ali_seq );
     foreach my $ali_cat ( @ali_cats )
     {
        if ( exists $upl_files{$ali_cat} )
        {
           foreach my $filen ( keys %{ $upl_files{$ali_cat} } )
           {
	      print $q->p( $filen );
           }   
        }
     }   
  }
  if ($upld_pseqs > 0)
  {
     if ($upld_pseqs == 1)
     {
	print $q->p("$upld_pseqs pasted sequence uploaded");
     }
     else
     {
	print $q->p("$upld_pseqs pasted sequences uploaded");
     }
  }
# alignment type, ie progressive or tree, should be set in form_proc.pl
# once it is clear how many segments there are
# In advanced the user should only be able to do one 1Dchange and it will
# set all 1D gap pens to that value
  print	$q->hidden( -name => "align_type", -default => "automatic",
          -override => 1 ),
        $q->hidden( -name => "1D_open_stst", -default => "-150",
	  -override => 1 ),
	$q->hidden( -name => "1D_elong_stst", -default => "-50",
	  -override => 1 ),
	$q->hidden( -name => "1D_open_stse", -default => "-100",
	  -override => 1),
	$q->hidden( -name => "1D_elong_stse", -default => "0",
	  -override => 1),
        $q->hidden( -name => "1D_open_sese", -default => "-450",
	  -override => 1),
	$q->hidden( -name => "1D_elong_sese", -default => "-50",
	  -override => 1),
        $q->hidden( -name => "1D_open_prof", -default => "-300",
	  -override => 1),
	$q->hidden( -name => "1D_elong_prof", -default => "0",
	  -override => 1),
	$q->hidden( -name => "2D_1", -default => "3.5",
	  -override => 1),
	$q->hidden( -name => "2D_2", -default => "3.5",
	  -override => 1),
	$q->hidden( -name => "2D_3", -default => "3.5",
	  -override => 1),
	$q->hidden( -name => "2D_4", -default => "0.2",
	  -override => 1),
	$q->hidden( -name => "2D_5", -default => "4.0",
	  -override => 1),
	$q->hidden( -name => "2D_6", -default => "6.5",
	  -override => 1),
	$q->hidden( -name => "2D_7", -default => "2.0",
	  -override => 1),
	$q->hidden( -name => "2D_8", -default => "0.0",
	  -override => 1),
	$q->hidden( -name => "2D_9", -default => "0",
	  -override => 1),
	$q->hidden( -name => "3D_open", -default => "0",
	  -override => 1 ),
	$q->hidden( -name => "3D_elong", -default => "2",
	  -override => 1 ),
	$q->hidden( -name => "fw_1", -default => "1",
	  -override => 1 ),
	$q->hidden( -name => "fw_2", -default => "1",
	  -override => 1 ),
	$q->hidden( -name => "fw_3", -default => "1",
	  -override => 1 ),
	$q->hidden( -name => "fw_4", -default => "1",
	  -override => 1 ),
	$q->hidden( -name => "fw_5", -default => "1",
	  -override => 1 ),
	$q->hidden( -name => "fw_6", -default => "0",
	  -override => 1 ),
	$q->hidden( -name => "max_gap", -default => "20",
	  -override => 1 ),
	$q->hidden( -name => "RMS_cutoff", -default => "3.5",
	  -override => 1 ),
	$q->hidden( -name => "overhangs", -default => "0",
	  -override => 1 ),
	$q->hidden( -name => "fit", -default => "True",
	  -override => 1 ),
	$q->hidden( -name => "improve", -default => "True",
	  -override => 1 ),
	$q->hidden( -name => "write_whole", -default => "False",
	  -override => 1 ),
	$q->hidden( -name => "gap-gap_score", -default => "0",
	  -override => 1 ),
	$q->hidden( -name => "gap-res_score", -default => "0",
	  -override => 1 ),
	$q->br,
	$q->submit( -value => "Submit" ),
	$q->reset(),
	$q->br,
	$q->end_form();
	
  # create form to call advanced view
  print $q->start_form( -method => "get" ),
        $q->hidden( -name => "caller", -default => "str-seq",
	  -override => 1 ),
	$q->hidden( -name => "upld_pseqs", -default => $upld_pseqs,
          -override => 1),
	$q->hidden( -name => "job_name", -default => $job_name,
          -override => 1),
	$q->hidden( -name => "email", -default => $email,
          -override => 1);
  # pass default structure segments
  if ( exists $upl_files{'str'} )
  {
     foreach my $filen ( keys %{ $upl_files{'str'} } )
     {
        print $q->hidden( 
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
        print $q->hidden( 
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
        print $q->hidden(
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
        print $q->hidden( 
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
  print $q->hidden( -name => "ali_files", -default => $ali_files,
          -override => 1 ),
        $q->submit( -name => "state", -value => "Advanced" ),
	$q->end_form();
  end($q);	
}


# generate default 2-step sequence-sequence alignment form page
# when submitted SALIGN will first align the two sets of
# sequences independently and then align the two alignments to
# each other using a profile-profile alignment. 
# step 1; for each set: 
# no of seqs: 2-30 => tree, 31-500 => progressive, >500 => no realignment
sub twostep_sese
{
  my $q = shift;
  my $email = shift;
  my $upl_files_ref = shift;
  my $upld_pseqs = shift;
  my $job_name = shift;
  my $lib_PDBs_ref = shift;
  my %upl_files = %$upl_files_ref;
  my %lib_PDBs = %$lib_PDBs_ref;
  
  start($q);
  print	$q->a({-href=>'/salign/salign_help.html#ali_cat_choice'},"Choice of alignment category:"), 
        $q->b("&nbsp Sequence-sequence alignment"),
        $q->p("Step 1: The two sets of sequences will be multiply aligned independently"),
	$q->p("Step 2: The resulting alignments from step 1 will be aligned to each other"),
	$q->hr,
        $q->start_form( -method => "post", -action => "/salign-cgi/form_proc.cgi" ),
	$q->hidden( -name => "tool", -default => "2s_sese", 
	  -override => 1),
        $q->hidden( -name => "job_name", -default => $job_name,
          -override => 1),
	$q->hidden( -name => "email", -default => $email,
          -override => 1),
	$q->hidden( -name => "upld_pseqs", -default => $upld_pseqs,
          -override => 1);
  # Show uploaded ali files and no of pasted seqs
  print $q->p("Uploaded alignment files");
  if ( exists $upl_files{'ali_stse'} )
  {
     foreach my $filen ( keys %{ $upl_files{'ali_stse'} } )
     {
        print $q->p( $filen );
     }   
  }
  if ( exists $upl_files{'ali_seq'} )
  {
     foreach my $filen ( keys %{ $upl_files{'ali_seq'} } )
     {
	print $q->p( $filen );
     }   
  }
  if ($upld_pseqs > 0)
  {
     if ($upld_pseqs == 1)
     {
	print $q->p("$upld_pseqs pasted sequence uploaded");
     }
     else
     {
	print $q->p("$upld_pseqs pasted sequences uploaded");
     }
  }
  print	$q->hidden( -name => "align_type", -default => "automatic",
          -override => 1 ),
        $q->hidden( -name => "1D_open_sese", -default => "-450",
	  -override => 1 ),
	$q->hidden( -name => "1D_elong_sese", -default => "-50",
	  -override => 1 ),
        $q->hidden( -name => "1D_open_prof", -default => "-300",
	  -override => 1),
	$q->hidden( -name => "1D_elong_prof", -default => "0",
	  -override => 1),
	$q->hidden( -name => "overhangs", -default => "0",
	  -override => 1 ),
	$q->hidden( -name => "improve", -default => "True",
	  -override => 1 ),
	$q->hidden( -name => "gap-gap_score", -default => "0",
	  -override => 1 ),
	$q->hidden( -name => "gap-res_score", -default => "0",
	  -override => 1 ),
	$q->br,
	$q->submit( -value => "Submit" ),
	$q->reset(),
	$q->br,
	$q->end_form();
	
  # create form to call advanced view
  print $q->start_form( -method => "get" ),
	$q->hidden( -name => "caller", -default => "2s_sese",
	  -override => 1 ),
	$q->hidden( -name => "upld_pseqs", -default => $upld_pseqs,
          -override => 1),
	$q->hidden( -name => "job_name", -default => $job_name,
          -override => 1),
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
        print $q->hidden( 
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
        print $q->hidden( 
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
  print $q->hidden( -name => "ali_files", -default => $ali_files,
          -override => 1 ),
	$q->hidden( -name => "structures", -default => $structures,
	  -override => 1 ),
        $q->submit( -name => "state", -value => "Advanced" ),
	$q->end_form();
  end($q);	
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
  
  my $page = $q->a({-href=>'/salign/salign_help.html#ali_cat_choice'},"Choice of alignment category:").
        $q->b("&nbsp Sequence-sequence alignment").
        $q->p("All uploaded sequences will be multiply aligned").
	$q->hr.
        $q->start_form( -method => "post", -action => "/salign-cgi/form_proc.cgi" ).
	$q->hidden( -name => "tool", -default => "1s_sese", 
	  -override => 1).
        $q->hidden( -name => "job_name", -default => $job_name,
          -override => 1).
	$q->hidden( -name => "email", -default => $email,
          -override => 1).
	$q->hidden( -name => "upld_pseqs", -default => $upld_pseqs,
          -override => 1);
  # Show uploaded ali files and no of pasted seqs
  if ( exists $upl_files{'ali_seq'} )
  {
     $page .= $q->p("Uploaded alignment files");
     foreach my $filen ( keys %{ $upl_files{'ali_seq'} } )
     {
	$page .= $q->p( $filen );
     }   
  }
  if ($upld_pseqs > 0)
  {
     if ($upld_pseqs == 1)
     {
	$page .= $q->p("$upld_pseqs pasted sequence uploaded");
     }
     else
     {
	$page .= $q->p("$upld_pseqs pasted sequences uploaded");
     }
  }
  $page .=$q->hidden( -name => "align_type", -default => "automatic",
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
	
  $page .= $q->start_form( -method => "get" ).
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
  $page .= $q->hidden( -name => "ali_files", -default => $ali_files,
          -override => 1 ).
        $q->submit( -name => "state", -value => "Advanced" ).
	$q->end_form();
  return $page;
}

# generate advanced structure-structure alignment form page
sub adv_stst
{
  my $q = shift;
  my $job_name = shift;
  my $email = shift;
  # Fetch all form values from default view.
  my %params;
  foreach my $param_name ($q->param)
  {
     $params{$param_name} = $q->param($param_name);
  }
 
  start($q);
  print	$q->a({-href=>'/salign/manual.html'}, "SALIGN Advanced Options"),
        $q->p("Depending on the choice of alignment category, some options may have no effect"),
	$q->hr,
        $q->start_multipart_form( -method => "post", -action => "/salign-cgi/form_proc.cgi" ),
	$q->hidden( -name => "tool", -default => "str_str_adv", 
	  -override => 1),
        $q->hidden( -name => "job_name", -default => $job_name,
          -override => 1),
	$q->hidden( -name => "email", -default => $email,
          -override => 1),
  	$q->a({-href=>'/salign/salign_help.html#ali_cat'}, "Alignment category"),
	$q->br,$q->br,
	$q->popup_menu(
	  -name    => "sa_feature",
	  -values  => [ "str_str", "1s_sese" ],
	  -default => "str_str",
	  -labels  => { "str_str" => "Structure-structure alignment",
			"1s_sese" => "Sequence-sequence alignment"    }
	),
	$q->br,$q->br,
  	$q->a({-href=>'/salign/salign_help.html#segments'}, "Specify PDB segments");
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
     print $q->p("Uploaded structure files");
     foreach my $str_name ( keys %{ $segments{'upl'} } )
     {
        print $q->i("$str_name&nbsp"),
              $q->textarea( 
	        -name => "uplsegm_$str_name", 
	        -cols => "15", 
	        -rows => "2", 
	        -default => $segments{'upl'}{$str_name},
		-override => 1
	      ),
	      $q->br;
     }
  }
  if ( exists $segments{'lib'} )
  {
     print $q->p("Structures from SALIGN PDB library");
     foreach my $str_name ( keys %{ $segments{'lib'} } )
     {
        print $q->i("$str_name&nbsp"),
              $q->textarea( 
	        -name => "libsegm_$str_name", 
	        -cols => "15", 
	        -rows => "2", 
	        -default => $segments{'lib'}{$str_name},
		-override => 1
	      ),
	      $q->br;
     }
  }

  print	$q->br,
	$q->a({-href=>'/salign/manual.html#ali_type'}, "Alignment type"),
	$q->b("&nbsp"),
	$q->radio_group(
	  -name    => "align_type",
	  -values  => [ "progressive","tree","automatic" ],
	  -default => "automatic",
	  -labels  => { "automatic"   => "",
	                "progressive" => "Progressive ",
			"tree"        => "Tree "          }
	),  
	$q->a({-href=>'/salign/salign_help.html#ali_type'}, "Optimal"),
	$q->br, $q->br,
	$q->a({-href=>'/salign/salign_help.html#1D_gap_pen'}, "1D gap penalties"),
	$q->br, $q->br,
	$q->i("Opening: "),
	$q->textfield( -name => "1D_open_usr", -default => "Default",
	  -size => "7" ),
	$q->i("&nbsp Extension: "),
	$q->textfield( -name => "1D_elong_usr", -default => "Default",
	  -size => "7" ),
  	$q->hidden( -name => "1D_open_stst", -default => "-150",
	  -override => 1 ),
	$q->hidden( -name => "1D_elong_stst", -default => "-50",
	  -override => 1 ),
	$q->hidden( -name => "1D_open_sese", -default => "-450",
	  -override => 1),
	$q->hidden( -name => "1D_elong_sese", -default => "-50",
	  -override => 1),
	$q->br, $q->br,
#	$q->hidden( -name => "3D_open", -default => "0",
#	  -override => 1 ),
#	$q->hidden( -name => "3D_elong", -default => "3",
#	  -override => 1 ),
	$q->a({-href=>'/salign/manual.html#3D_gap_pen'}, "3D gap penalties"),
	$q->br, $q->br,
	$q->i("Opening: "),
	$q->textfield( -name => "3D_open", -default => "0",
	  -size => "10" ),
	$q->i("&nbsp Extension: "),
	$q->textfield( -name => "3D_elong", -default => "2",
	  -size => "10" ),
	$q->hidden( -name => "fw_1", -default => "1",
	  -override => 1 ),
	$q->hidden( -name => "fw_2", -default => "1",
	  -override => 1 ),
	$q->hidden( -name => "fw_3", -default => "1",
	  -override => 1 ),
	$q->hidden( -name => "fw_4", -default => "1",
	  -override => 1 ),
	$q->hidden( -name => "fw_5", -default => "1",
	  -override => 1 ),
	$q->hidden( -name => "fw_6", -default => "0",
	  -override => 1 ),
#        $q->br, $q->br,
#	$q->a({-href=>'/salign/manual.html#feat_wts'}, "Feature weights"),
#	$q->br, $q->br,
#	$q->i("Feature 1: "),
#	$q->textfield( -name => "fw_1", -default => "1",
#	  -size => "5" ),
#	$q->i("&nbsp Feature 2: "),
#	$q->textfield( -name => "fw_2", -default => "1",
#	  -size => "5" ),
#	$q->i("&nbsp Feature 3: "),
#	$q->textfield( -name => "fw_3", -default => "1",
#	  -size => "5" ),
#	$q->br,
#	$q->i("Feature 4: "),
#	$q->textfield( -name => "fw_4", -default => "1",
#	  -size => "5" ),
#	$q->i("&nbsp Feature 5: "),
#	$q->textfield( -name => "fw_5", -default => "1",
#	  -size => "5" ),
#	$q->i("&nbsp Feature 6: "),
#	$q->textfield( -name => "fw_6", -default => "0",
#	  -size => "5" ),
	$q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#wt_mtx'}, "External weight matrix"),
	$q->br, $q->br,
        $q->filefield( -name => "weight_mtx" ),
	$q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#rms_cutoff'}, "RMS cut-off for average number of equivalent positions determination"),
	$q->br, $q->br,
	$q->textfield( -name => "RMS_cutoff", -default => "3.5",
	  -size => "5"),
	$q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#max_gap'}, "Max gap length"),
	$q->br, $q->br,
	$q->textfield( -name => "max_gap", -default => "20",
	  -size => "5"),
	$q->br, $q->br,
#	$q->hidden( -name => "overhangs", -default => "0",
#	  -override => 1 ),
	$q->a({-href=>'/salign/manual.html#overhang'}, "Overhangs"),
	$q->br, $q->br,
	$q->textfield( -name => "overhangs", -default => "0",
	  -size => "5"),
	$q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#gap_gap_score'}, "Gap-gap score"),
	$q->br, $q->br,
	$q->textfield( -name => "gap-gap_score", -default => "0",
	  -size => "5"),
	$q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#gap_res_score'}, "Gap-residue score"),
	$q->br, $q->br,
	$q->textfield( -name => "gap-res_score", -default => "0",
	  -size => "5"),
	$q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#fit'}, "Fit"),
	$q->b("&nbsp"),
	$q->radio_group(
	  -name    => "fit",
	  -values  => [ "True", "False" ],
	  -default => "True",
	  -labels  => { "True" => "True ",
			"False" => "False" }
	),
	$q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#improve'}, "Improve Alignment"),
	$q->b("&nbsp"),
	$q->radio_group(
	  -name    => "improve",
	  -values  => [ "True", "False" ],
	  -default => "True",
	  -labels  => { "True" => "True ",
	                "False" => "False" }
	), 
	$q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#write_whole'}, "Write whole PDB"),
	$q->b("&nbsp"),
	$q->radio_group(
	  -name    => "write_whole",
	  -values  => [ "True", "False" ],
	  -default => "False",
	  -labels  => { "True" => "True ",
	                "False" => "False" }
	), 
	$q->br, $q->br,
	$q->submit( -value => "Submit" ),
	$q->reset(),
	$q->end_form();
  end($q);	
}


# generate advanced structure-sequence alignment form page
sub adv_stse
{
  my $q = shift;
  my $job_name = shift;
  my $email = shift;
  # Fetch all form values from default view.
  my %params;
  foreach my $param_name ($q->param)
  {
     $params{$param_name} = $q->param($param_name);
  }
  my $upld_pseqs = $params{'upld_pseqs'};
  
  start($q);
  print	$q->a({-href=>'/salign/manual.html'}, "SALIGN Advanced Options"),
        $q->p("Depending on the choice of alignment category, some options may have no effect"),
	$q->hr,
        $q->start_multipart_form( -method => "post", -action => "/salign-cgi/form_proc.cgi" ),
	$q->hidden( -name => "tool", -default => "str_seq_adv", 
	  -override => 1),
	$q->hidden( -name => "upld_pseqs", -default => $upld_pseqs,
          -override => 1),
        $q->hidden( -name => "job_name", -default => $job_name,
          -override => 1),
	$q->hidden( -name => "email", -default => $email,
          -override => 1),
  	$q->a({-href=>'/salign/salign_help.html#ali_cat'}, "Alignment category"),
	$q->br,$q->br,
	$q->popup_menu(
	  -name    => "sa_feature",
	  -values  => [ "str_seq", "1s_sese" ],
	  -default => "str_seq",
	  -labels  => { "str_seq" => "Structure-sequence alignment",
			"1s_sese" => "Sequence-sequence alignment"    }
	),
	$q->br,$q->br,
  	$q->a({-href=>'/salign/salign_help.html#segments'}, "Specify PDB segments");
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
     print $q->p("Uploaded structure files");
     foreach my $str_name ( keys %{ $segments{'upl'} } )
     {
        print $q->i("$str_name&nbsp"),
              $q->textarea( 
	        -name => "uplsegm_$str_name", 
	        -cols => "15", 
	        -rows => "2", 
	        -default => $segments{'upl'}{$str_name},
		-override => 1
	      ),
	      $q->br;
     }
  }
  if ( exists $segments{'lib'} )
  {
     print $q->p("Structures from SALIGN PDB library");
     foreach my $str_name ( keys %{ $segments{'lib'} } )
     {
        print $q->i("$str_name&nbsp"),
              $q->textarea( 
	        -name => "libsegm_$str_name", 
	        -cols => "15", 
	        -rows => "2", 
	        -default => $segments{'lib'}{$str_name},
		-override => 1
	      ),
	      $q->br;
     }
  }
  # Present uploaded ali files and no of pasted seqs
  unless ( $params{'ali_files'} eq '' )
  {
     print $q->p("Uploaded alignment files");
     my @ali_files = split ( " ",$params{'ali_files'} );
     foreach my $filen ( @ali_files )
     {
        print $q->p( $filen );
     }
  }
  if ($upld_pseqs > 0)
  {
     if ($upld_pseqs == 1)
     {
	print $q->p("$upld_pseqs pasted sequence uploaded");
     }
     else
     {
	print $q->p("$upld_pseqs pasted sequences uploaded");
     }
  }
  print	$q->br,
	$q->a({-href=>'/salign/manual.html#ali_type'}, "Alignment type"),
	$q->b("&nbsp"),
	$q->radio_group(
	  -name    => "align_type",
	  -values  => [ "progressive","tree","automatic" ],
	  -default => "automatic",
	  -labels  => { "automatic"   => "",
	                "progressive" => "Progressive ",
			"tree"        => "Tree "          }
	),  
	$q->a({-href=>'/salign/salign_help.html#ali_type'}, "Optimal"),
	$q->br, $q->br,
	$q->a({-href=>'/salign/salign_help.html#1D_gap_pen'}, "1D gap penalties"),
	$q->br, $q->br,
	$q->i("Opening: "),
	$q->textfield( -name => "1D_open_usr", -default => "Default",
	  -size => "7" ),
	$q->i("&nbsp Extension: "),
	$q->textfield( -name => "1D_elong_usr", -default => "Default",
	  -size => "7" ),
  	$q->hidden( -name => "1D_open_stst", -default => "-150",
	  -override => 1 ),
	$q->hidden( -name => "1D_elong_stst", -default => "-50",
	  -override => 1 ),
	$q->hidden( -name => "1D_open_stse", -default => "-100",
	  -override => 1),
	$q->hidden( -name => "1D_elong_stse", -default => "0",
	  -override => 1),
        $q->hidden( -name => "1D_open_sese", -default => "-450",
	  -override => 1),
	$q->hidden( -name => "1D_elong_sese", -default => "-50",
	  -override => 1),
	$q->hidden( -name => "1D_open_prof", -default => "-300",
	  -override => 1),
	$q->hidden( -name => "1D_elong_prof", -default => "0",
	  -override => 1),
        $q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#2D_gap_pen'}, "2D gap penalties"),
	$q->br, $q->br,
	$q->i("Helicity: "),
	$q->textfield( -name => "2D_1", -default => "3.5",
	  -size => "5" ),
	$q->i("Strandedness: "),
	$q->textfield( -name => "2D_2", -default => "3.5",
	  -size => "5" ),
	$q->i("Burial:"),
	$q->textfield( -name => "2D_3", -default => "3.5",
	  -size => "5" ),
	$q->i("Local straightness: "),
	$q->textfield( -name => "2D_4", -default => "0.2",
	  -size => "5" ),
	$q->i("Gap spanning distance: "),
	$q->textfield( -name => "2D_5", -default => "4.0",
	  -size => "5" ),
	$q->br,  
  	$q->i("Optimal gap distance: "),
	$q->textfield( -name => "2D_6", -default => "6.5",
	  -size => "5" ),
	$q->i("Exponent of gap spanning distance: "),
	$q->textfield( -name => "2D_7", -default => "2.0",
	  -size => "5" ),
	$q->i("Diagonal gap penalty: "),
	$q->textfield( -name => "2D_8", -default => "0.0",
	  -size => "5" ),
	$q->hidden( -name => "2D_9", -default => "0",
	  -override => 1 ),
	$q->br, $q->br,
#	$q->hidden( -name => "3D_open", -default => "0",
#	  -override => 1 ),
#	$q->hidden( -name => "3D_elong", -default => "3",
#	  -override => 1 ),
	$q->a({-href=>'/salign/manual.html#3D_gap_pen'}, "3D gap penalties"),
	$q->br, $q->br,
	$q->i("Opening: "),
	$q->textfield( -name => "3D_open", -default => "0",
	  -size => "10" ),
	$q->i("&nbsp Extension: "),
	$q->textfield( -name => "3D_elong", -default => "2",
	  -size => "10" ),
	$q->hidden( -name => "fw_1", -default => "1",
	  -override => 1 ),
	$q->hidden( -name => "fw_2", -default => "1",
	  -override => 1 ),
	$q->hidden( -name => "fw_3", -default => "1",
	  -override => 1 ),
	$q->hidden( -name => "fw_4", -default => "1",
	  -override => 1 ),
	$q->hidden( -name => "fw_5", -default => "1",
	  -override => 1 ),
	$q->hidden( -name => "fw_6", -default => "0",
	  -override => 1 ),
#        $q->br, $q->br,
#	$q->a({-href=>'/salign/manual.html#feat_wts'}, "Feature weights"),
#	$q->br, $q->br,
#	$q->i("Feature 1: "),
#	$q->textfield( -name => "fw_1", -default => "1",
#	  -size => "5" ),
#	$q->i("&nbsp Feature 2: "),
#	$q->textfield( -name => "fw_2", -default => "1",
#	  -size => "5" ),
#	$q->i("&nbsp Feature 3: "),
#	$q->textfield( -name => "fw_3", -default => "1",
#	  -size => "5" ),
#	$q->br,
#	$q->i("Feature 4: "),
#	$q->textfield( -name => "fw_4", -default => "1",
#	  -size => "5" ),
#	$q->i("&nbsp Feature 5: "),
#	$q->textfield( -name => "fw_5", -default => "1",
#	  -size => "5" ),
#	$q->i("&nbsp Feature 6: "),
#	$q->textfield( -name => "fw_6", -default => "0",
#	  -size => "5" ),
	$q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#wt_mtx'}, "External weight matrix"),
	$q->br, $q->br,
        $q->filefield( -name => "weight_mtx" ),
	$q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#rms_cutoff'}, "RMS cut-off for average number of equivalent positions determination"),
	$q->br, $q->br,
	$q->textfield( -name => "RMS_cutoff", -default => "3.5",
	  -size => "5"),
	$q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#max_gap'}, "Max gap length"),
	$q->br, $q->br,
	$q->textfield( -name => "max_gap", -default => "20",
	  -size => "5"),
	$q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#overhang'}, "Overhangs"),
	$q->br, $q->br,
	$q->textfield( -name => "overhangs", -default => "0",
	  -size => "5"),
	$q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#gap_gap_score'}, "Gap-gap score"),
	$q->br, $q->br,
	$q->textfield( -name => "gap-gap_score", -default => "0",
	  -size => "5"),
	$q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#gap_res_score'}, "Gap-residue score"),
	$q->br, $q->br,
	$q->textfield( -name => "gap-res_score", -default => "0",
	  -size => "5"),
	$q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#fit'}, "Fit"),
	$q->b("&nbsp"),
	$q->radio_group(
	  -name    => "fit",
	  -values  => [ "True", "False" ],
	  -default => "True",
	  -labels  => { "True" => "True ",
			"False" => "False" }
	),
	$q->br, $q->br,
	$q->a({-href=>'/salign/manual.html#improve'}, "Improve Alignment"),
	$q->b("&nbsp"),
	$q->radio_group(
	  -name    => "improve",
	  -values  => [ "True", "False" ],
	  -default => "True",
	  -labels  => { "True" => "True ",
	                "False" => "False" }
	), 
	$q->br, $q->br,
	$q->hidden( -name => "write_whole", -default => "False",
	  -override => 1 ),
	$q->submit( -value => "Submit" ),
	$q->reset(),
	$q->end_form();
  end($q);	
}
  

# generate advanced sequence-sequence alignment form page
sub adv_sese
{
  my $q = shift;
  my $job_name = shift;
  my $email = shift;

  # Fetch all form values from default view.
  my %params;
  foreach my $param_name ($q->param)
  {
     $params{$param_name} = $q->param($param_name);
  }
  my $upld_pseqs = $params{'upld_pseqs'};
  my $structures = $params{'structures'};
  
  start($q);
  print	$q->a({-href=>'/salign/manual.html'}, "SALIGN Advanced Options");
  if ( $params{'caller'} eq '2s_sese' )
  {
     print $q->p("Depending on the choice of alignment category, some options may have no effect");
  }
  print	$q->hr,
        $q->start_multipart_form( -method => "post", -action => "/salign-cgi/form_proc.cgi" ),
	$q->hidden( -name => "tool", -default => "sese_adv", 
	  -override => 1),
	$q->hidden( -name => "upld_pseqs", -default => $upld_pseqs,
          -override => 1),
	$q->hidden( -name => "structures", -default => $structures,
          -override => 1),
        $q->hidden( -name => "job_name", -default => $job_name,
          -override => 1),
	$q->hidden( -name => "email", -default => $email,
          -override => 1);
  if ( $params{'caller'} eq '2s_sese' )
  {
     print $q->a({-href=>'/salign/salign_help.html#ali_cat'}, "Alignment category"),
     $q->br,$q->br;
     if ( $structures == 1 )
     {
        print $q->popup_menu(
                -name    => "sa_feature",
                -values  => [ "2s_sese","str_seq","1s_sese" ],
                -default => "2s_sese",
                -labels  => { "2s_sese" => "Two step sequence-sequence alignment",
                              "str_seq" => "Structure-sequence alignment",
		              "1s_sese" => "One step sequence-sequence alignment"  }
              ),
	      $q->br,$q->br,
  	      $q->a({-href=>'/salign/salign_help.html#segments'}, "Specify PDB segments");
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
           print $q->p("Uploaded structure files");
           foreach my $str_name ( keys %{ $segments{'upl'} } )
           {
              print $q->i("$str_name&nbsp"),
                    $q->textarea( 
	              -name => "uplsegm_$str_name", 
	              -cols => "15", 
	              -rows => "2", 
	              -default => $segments{'upl'}{$str_name},
		      -override => 1
	            ),
	            $q->br;
           }
        }
        if ( exists $segments{'lib'} )
        {
           print $q->p("Structures from SALIGN PDB library");
           foreach my $str_name ( keys %{ $segments{'lib'} } )
           {
              print $q->i("$str_name&nbsp"),
                    $q->textarea( 
	              -name => "libsegm_$str_name", 
	              -cols => "15", 
	              -rows => "2", 
	              -default => $segments{'lib'}{$str_name},
	   	      -override => 1
	            ),
	            $q->br;
           }
        }
     }
     else
     {
        print $q->popup_menu(
                -name    => "sa_feature",
                -values  => [ "2s_sese","1s_sese" ],
                -default => "2s_sese",
                -labels  => { "2s_sese" => "Two step sequence-sequence alignment",
		              "1s_sese" => "One step sequence-sequence alignment"  }
              );
     }
  }  
  else #called from 1step seq seq
  {
     print $q->hidden( -name => "sa_feature", -default => "1s_sese",
             -override => 1 );
  }
  # Present uploaded ali files and no of pasted seqs
  unless ( $params{'ali_files'} eq '' )
  {
     print $q->p("Uploaded alignment files");
     my @ali_files = split ( " ",$params{'ali_files'} );
     foreach my $filen ( @ali_files )
     {
        print $q->p( $filen );
     }
  }
  if ($upld_pseqs > 0)
  {
     if ($upld_pseqs == 1)
     {
	print $q->p("$upld_pseqs pasted sequence uploaded");
     }
     else
     {
	print $q->p("$upld_pseqs pasted sequences uploaded");
     }
  }
  print	$q->br,
	$q->a({-href=>'/salign/manual.html#ali_type'}, "Alignment type"),
	$q->b("&nbsp"),
	$q->radio_group(
	  -name    => "align_type",
	  -values  => [ "progressive","tree","automatic" ],
	  -default => "automatic",
	  -labels  => { "automatic"   => "",
	                "progressive" => "Progressive ",
			"tree"        => "Tree "          }
	),  
	$q->a({-href=>'/salign/salign_help.html#ali_type'}, "Optimal"),
	$q->br, $q->br;
  if ( $structures == 1 )
  {
     print $q->a({-href=>'/salign/salign_help.html#1D_gap_pen'}, "1D gap penalties"),
	   $q->br, $q->br,
   	   $q->i("Opening: "),
	   $q->textfield( -name => "1D_open_usr", -default => "Default",
	     -size => "7" ),
	   $q->i("&nbsp Extension: "),
	   $q->textfield( -name => "1D_elong_usr", -default => "Default",
	     -size => "7" ),
  	   $q->hidden( -name => "1D_open_stst", -default => "-150",
	     -override => 1 ),
	   $q->hidden( -name => "1D_elong_stst", -default => "-50",
	     -override => 1 ),
	   $q->hidden( -name => "1D_open_stse", -default => "-100",
	     -override => 1),
	   $q->hidden( -name => "1D_elong_stse", -default => "0",
	     -override => 1),
           $q->hidden( -name => "1D_open_sese", -default => "-450",
	     -override => 1),
	   $q->hidden( -name => "1D_elong_sese", -default => "-50",
	     -override => 1),
           $q->hidden( -name => "1D_open_prof", -default => "-300",
	     -override => 1),
	   $q->hidden( -name => "1D_elong_prof", -default => "0",
	     -override => 1),
           $q->br, $q->br,
	   $q->a({-href=>'/salign/manual.html#2D_gap_pen'}, "2D gap penalties"),
	   $q->br, $q->br,
	   $q->i("Helicity: "),
	   $q->textfield( -name => "2D_1", -default => "3.5",
	     -size => "5" ),
	   $q->i("Strandedness: "),
	   $q->textfield( -name => "2D_2", -default => "3.5",
	     -size => "5" ),
	   $q->i("Burial: "),
	   $q->textfield( -name => "2D_3", -default => "3.5",
	     -size => "5" ),
	   $q->i("Local straightness: "),
	   $q->textfield( -name => "2D_4", -default => "0.2",
	     -size => "5" ),
	   $q->i("Gap spanning distance: "),
	   $q->textfield( -name => "2D_5", -default => "4.0",
	     -size => "5" ),
	   $q->br,  
  	   $q->i("Optimal gap distance: "),
	   $q->textfield( -name => "2D_6", -default => "6.5",
	     -size => "5" ),
	   $q->i("Exponent of gap spanning distance: "),
	   $q->textfield( -name => "2D_7", -default => "2.0",
	     -size => "5" ),
	   $q->i("Diagonal gap penalty: "),
	   $q->textfield( -name => "2D_8", -default => "0.0",
	     -size => "5" ),
	   $q->hidden( -name => "2D_9", -default => "0",
	     -override => 1 ),
	   $q->br, $q->br,
#	   $q->hidden( -name => "3D_open", -default => "0",
#	     -override => 1 ),
#	   $q->hidden( -name => "3D_elong", -default => "3",
#	     -override => 1 ),
	   $q->a({-href=>'/salign/manual.html#3D_gap_pen'}, "3D gap penalties"),
	   $q->br, $q->br,
	   $q->i("Opening: "),
	   $q->textfield( -name => "3D_open", -default => "0",
	     -size => "10" ),
	   $q->i("&nbsp Extension: "),
	   $q->textfield( -name => "3D_elong", -default => "2",
	     -size => "10" ),
	   $q->hidden( -name => "fw_1", -default => "0",
	     -override => 1 ),
	   $q->hidden( -name => "fw_2", -default => "1",
	     -override => 1 ),
 	   $q->hidden( -name => "fw_3", -default => "0",
	     -override => 1 ),
	   $q->hidden( -name => "fw_4", -default => "0",
	     -override => 1 ),
	   $q->hidden( -name => "fw_5", -default => "0",
	     -override => 1 ),
	   $q->hidden( -name => "fw_6", -default => "0",
	     -override => 1 ),
#           $q->br, $q->br,
#	   $q->a({-href=>'/salign/manual.html#feat_wts'}, "Feature weights"),
#	   $q->br, $q->br,
#	   $q->i("Feature 1: "),
#	   $q->textfield( -name => "fw_1", -default => "0",
#	     -size => "5" ),
 #	   $q->i("&nbsp Feature 2: "),
#	   $q->textfield( -name => "fw_2", -default => "1",
#	     -size => "5" ),
# 	   $q->i("&nbsp Feature 3: "),
#	   $q->textfield( -name => "fw_3", -default => "0",
#	     -size => "5" ),
#	   $q->br,
 # 	   $q->i("Feature 4: "),
#	   $q->textfield( -name => "fw_4", -default => "0",
#	     -size => "5" ),
#	   $q->i("&nbsp Feature 5: "),
#	   $q->textfield( -name => "fw_5", -default => "0",
#	     -size => "5" ),
#	   $q->i("&nbsp Feature 6: "),
#	   $q->textfield( -name => "fw_6", -default => "0",
#	     -size => "5" ),
	   $q->br, $q->br,
	   $q->a({-href=>'/salign/manual.html#wt_mtx'}, "External weight matrix"),
	   $q->br, $q->br,
           $q->filefield( -name => "weight_mtx" ),
	   $q->br, $q->br,
	   $q->a({-href=>'/salign/manual.html#rms_cutoff'}, "RMS cut-off for average number of equivalent positions determination"),
	   $q->br, $q->br,
	   $q->textfield( -name => "RMS_cutoff", -default => "3.5",
	     -size => "5"),
	   $q->br, $q->br,
	   $q->a({-href=>'/salign/manual.html#max_gap'}, "Max gap length"),
	   $q->br, $q->br,
	   $q->textfield( -name => "max_gap", -default => "20",
	     -size => "5"),
  	   $q->br, $q->br,
	   $q->a({-href=>'/salign/manual.html#overhang'}, "Overhangs"),
	   $q->br, $q->br,
	   $q->textfield( -name => "overhangs", -default => "0",
	     -size => "5"),
	   $q->br, $q->br,
	   $q->a({-href=>'/salign/manual.html#gap_gap_score'}, "Gap-gap score"),
	   $q->br, $q->br,
	   $q->textfield( -name => "gap-gap_score", -default => "0",
	     -size => "5"),
	   $q->br, $q->br,
	   $q->a({-href=>'/salign/manual.html#gap_res_score'}, "Gap-residue score"),
	   $q->br, $q->br,
	   $q->textfield( -name => "gap-res_score", -default => "0",
	     -size => "5"),
	   $q->br, $q->br,
	   $q->a({-href=>'/salign/manual.html#fit'}, "Fit"),
	   $q->b("&nbsp"),
	   $q->radio_group(
             -name    => "fit",
	     -values  => [ "True", "False" ],
	     -default => "True",
	     -labels  => { "True" => "True ",
		           "False" => "False" }
	   ),
	   $q->br, $q->br,
	   $q->a({-href=>'/salign/manual.html#improve'}, "Improve Alignment"),
	   $q->b("&nbsp"),
	   $q->radio_group(
	     -name    => "improve",
	     -values  => [ "True", "False" ],
	     -default => "True",
	     -labels  => { "True" => "True ",
	                   "False" => "False" }
	   ), 
	   $q->hidden( -name => "write_whole", -default => "False",
	     -override => 1 ),
	   $q->br, $q->br;
  }
  else
  {
     print $q->a({-href=>'/salign/salign_help.html#1D_gap_pen'}, "1D gap penalties"),
	   $q->br, $q->br,
   	   $q->i("Opening: "),
	   $q->textfield( -name => "1D_open_usr", -default => "Default",
	     -size => "7" ),
	   $q->i("&nbsp Extension: "),
	   $q->textfield( -name => "1D_elong_usr", -default => "Default",
	     -size => "7" ),
           $q->hidden( -name => "1D_open_sese", -default => "-450",
	     -override => 1 ),
	   $q->hidden( -name => "1D_elong_sese", -default => "-50",
	     -override => 1 ),
           $q->hidden( -name => "1D_open_prof", -default => "-300",
	     -override => 1),
	   $q->hidden( -name => "1D_elong_prof", -default => "0",
	     -override => 1),
	   $q->br, $q->br,
	   $q->a({-href=>'/salign/manual.html#overhang'}, "Overhangs"),
	   $q->br, $q->br,
	   $q->textfield( -name => "overhangs", -default => "0",
	     -size => "5"),
	   $q->br, $q->br,
	   $q->a({-href=>'/salign/manual.html#gap_gap_score'}, "Gap-gap score"),
	   $q->br, $q->br,
	   $q->textfield( -name => "gap-gap_score", -default => "0",
	     -size => "5"),
	   $q->br, $q->br,
	   $q->a({-href=>'/salign/manual.html#gap_res_score'}, "Gap-residue score"),
	   $q->br, $q->br,
	   $q->textfield( -name => "gap-res_score", -default => "0",
	     -size => "5"),
	   $q->br, $q->br,
	   $q->a({-href=>'/salign/manual.html#improve'}, "Improve Alignment"),
	   $q->b("&nbsp"),
	   $q->radio_group(
	     -name    => "improve",
	     -values  => [ "True", "False" ],
	     -default => "True",
	     -labels  => { "True" => "True ",
	                   "False" => "False" }
	   ), 
	   $q->br, $q->br;
  }
  print	$q->submit( -value => "Submit" ),
	$q->reset(),
	$q->end_form();
  end($q);	
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

1;
