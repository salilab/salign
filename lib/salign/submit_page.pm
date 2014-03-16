package salign::submit_page;

#NOTE: For 1D gap penalties (open and elong) the user can either set his own values or 
#leave them as default.
#Whereas a user value sets all 1D gap pens to that value, default sets different 1D gap pens
#(different gap pens == str-str 1D, str-seq 1D etc.)
#to different values. 

use strict;
use Fcntl qw( :DEFAULT :flock);
use DB_File;
use File::Find;
#use locale;
use constant MAX_POST_SIZE => 1_048_576; # Maximum upload size, 1 MB
use File::Copy;

#Enable users to upload files to our server
$CGI::DISABLE_UPLOADS = 0;
#Users not allowed to post more data than 1 MB 
$CGI::POST_MAX = MAX_POST_SIZE; 

# Location of PDB database
#my $pdb_database = "/netapp/database/pdb/uncompressed_files";
my $pdb_database = "/netapp/database/pdb/remediated/uncompressed_files";

# ========================= SUB ROUTINES ================================
sub fpmain
{  
  my ($self, $q) = @_;
  # Look for errors in the transfer process
  if ($q->cgi_error) { error($q, "Transfer error: " . $q->cgi_error); }

  # Fetch all form inputs.
  my $inputs;
  foreach my $param_name ($q->param) 
  {
    $inputs->{$param_name} = $q->param($param_name);
  }
  
  my $job_name = $inputs->{'job_name'};
  my $job = $self->resume_job($job_name);
  # All paths will be relative to the current directory (the job directory)
  chdir($job->directory) or die "Cannot change into job directory: $!";

  if ($inputs->{'tool'} eq "str_str")
  {
     return fp_str_str($self,$q,$job,$inputs,0);
  }
  elsif ($inputs->{'tool'} eq "str_seq")
  {
     return fp_str_seq($self,$q,$job,$inputs,0);
  }
  elsif ($inputs->{'tool'} eq "2s_sese")
  {
     return fp_twostep_sese($self,$q,$job,$inputs,0);
  }
  elsif ($inputs->{'tool'} eq "1s_sese")
  {
     return fp_onestep_sese($self,$q,$job,$inputs,'seqs',0);
  }
  else  # advanced views
  {
     return adv_views($self,$q,$job,$inputs);
  }
}

# Main sub for structure-structure alignments
sub fp_str_str
{
  my $self = shift;
  my $q = shift;
  my $job = shift;
  my $inputs = shift;
  my $adv = shift;
  my $conf_file = '/modbase5/home/salign/conf/salign.conf';
  # Read conf_file
  my $conf_ref = read_conf($conf_file);

  my $buffer_size = $conf_ref->{'BUFFER_SIZE'};
  my $max_dir_size = $conf_ref->{'MAX_DIR_SIZE'};
  my $static_dir = $conf_ref->{'STATIC_DIR'};
  my $max_open = $conf_ref->{'MAX_OPEN_TRIES'};
  
  my $job_dir = '.';
  my $upl_dir = $job_dir . '/upload';

  # set 1D gap pens to their str-str values or usr value
  if ( $adv == 1 )
  {
     if ( $inputs->{'1D_open_usr'} eq 'Default' )
     {
        $inputs->{'1D_open'} = $inputs->{'1D_open_stst'};
     }
     else { $inputs->{'1D_open'} = $inputs->{'1D_open_usr'}; }
     
     if ( $inputs->{'1D_elong_usr'} eq 'Default' )
     {
        $inputs->{'1D_elong'} = $inputs->{'1D_elong_stst'};
     }
     else { $inputs->{'1D_elong'} = $inputs->{'1D_elong_usr'}; }
  }
  else
  {
     # set 1Dgap pens to their str-str values
     $inputs->{'1D_open'} = $inputs->{'1D_open_stst'};
     $inputs->{'1D_elong'} = $inputs->{'1D_elong_stst'};
  }

  my ($str_segm_ref,$str_count) = strstr_inputs($q,$inputs,$adv,'str');
  my %str_segm = %$str_segm_ref;
  my $wt_mtx;
#  if ($inputs->{'fw_6'} != 0)
  unless ($inputs->{'weight_mtx'} eq "")
  {
     check_dir_size($q,$job_dir,$max_dir_size);
     unless ( -d $upl_dir )
     {
        mkdir $upl_dir
          or die "Can't create sub directory upload: $!\n";
     }
     # upload weight matrix 
     $wt_mtx = fp_file_upload($q,$upl_dir,$buffer_size,"weight_mtx",$max_open);
     #check that file is ascii
     my $ascii = ascii_chk($upl_dir,$wt_mtx);
     unless ($ascii == 1) 
     {
        error($q,"Non ascii file found where only ascii files allowed: $wt_mtx");
     }  
  } 

  my $str_dir;
  my $upl_strs;
  # if there are both uploaded strs and lib strs, gather them in a common dir
  if ( exists $str_segm{'upl'} && exists $str_segm{'lib'} )
  {
     #Hash uploaded structure files
     tie my %tie_hash, "DB_File", "$job_dir/upl_files.db", O_RDONLY
       or die "Cannot open tie to filetype DBM: $!";
     while ( my ($filen,$type) = each %tie_hash )
     {
        if ($type eq 'str') #save for use in sub cp_PBDs
        {
           $upl_strs->{$filen} = 1;
        }
     } 
     untie %tie_hash;
     $str_dir = cp_PDBs($str_segm_ref,$upl_dir,$static_dir,$job_dir,$upl_strs);
  }
  elsif ( exists $str_segm{'upl'} ) 
  { 
     $str_dir = 'upload';
  }
  else #only lib. copy to job dir (necessary for multiple entries of same pdb) 
  {
     $str_dir = cp_PDBs_noUpl($str_segm_ref,$static_dir,$job_dir); 
  }
  
  $str_segm_ref = OnePdbPerSegm($str_segm_ref,$job_dir, $str_dir);
  # create top file
  my $output_ali = "str-str_out.ali";
  strstr_topf($job_dir,$inputs,$static_dir,$str_segm_ref,$wt_mtx,'str-str.py',$output_ali,$str_dir);
  # write relevant inputs to DBM file
  my $memo_inp;
  $memo_inp->{'email'} = $inputs->{'email'};
#  $memo_inp->{'fit_coord'} = $inputs->{'fit_coord'};
  $memo_inp->{'tool'} = 'str_str';
  create_memo($memo_inp,$job_dir);
  return print_job_submission($self,$job, $inputs->{'email'});
}

# Main sub for structure sequence alignment
sub fp_str_seq
{
  my $self = shift;
  my $q = shift;
  my $job = shift;
  my $inputs = shift;
  my $adv = shift;
  my $conf_file = '/modbase5/home/salign/conf/salign.conf';
  # Read conf_file
  my $conf_ref = read_conf($conf_file);

  my $buffer_size = $conf_ref->{'BUFFER_SIZE'};
  my $max_dir_size = $conf_ref->{'MAX_DIR_SIZE'};
  my $static_dir = $conf_ref->{'STATIC_DIR'};
  my $max_open = $conf_ref->{'MAX_OPEN_TRIES'};
  
  my $job_dir = '.';
  my $upl_dir = $job_dir . '/upload';
  
  # check/fix inputs and get structure segments
  if ( $adv == 1 )
  {
     foreach my $i ( 1 .. 9 )
     { 
        if ( $inputs->{"2D_$i"} eq "" )
        {
           error($q,"You must specify all 2D gap penalties");
        }
     }
     # set 1D gap pens to their str-str values or usr value
     if ( $inputs->{'1D_open_usr'} eq 'Default' )
     {
        $inputs->{'1D_open'} = $inputs->{'1D_open_stst'};
     }
     else { $inputs->{'1D_open'} = $inputs->{'1D_open_usr'}; }
     
     if ( $inputs->{'1D_elong_usr'} eq 'Default' )
     {
        $inputs->{'1D_elong'} = $inputs->{'1D_elong_stst'};
     }
     else { $inputs->{'1D_elong'} = $inputs->{'1D_elong_usr'}; }
  }
  else
  {
     # set 1Dgap pens to their str-str values
     $inputs->{'1D_open'} = $inputs->{'1D_open_stst'};
     $inputs->{'1D_elong'} = $inputs->{'1D_elong_stst'};
  }
  my ($str_segm_ref,$str_count) = strstr_inputs($q,$inputs,$adv,'str');
  my %str_segm = %$str_segm_ref;
  #upload weight mtx if any
  my $wt_mtx;
#  if ($inputs->{'fw_6'} != 0)
  unless ($inputs->{'weight_mtx'} eq "")
  {
     check_dir_size($q,$job_dir,$max_dir_size);
     unless ( -d $upl_dir )
     {
        mkdir $upl_dir
          or die "Can't create sub directory upload: $!\n";
     }
     # upload weight matrix 
     $wt_mtx = fp_file_upload($q,$upl_dir,$buffer_size,"weight_mtx",$max_open);
     #check that file is ascii
     my $ascii = ascii_chk($upl_dir,$wt_mtx);
     unless ($ascii == 1) 
     {
        error($q,"Non ascii file found where only ascii files allowed: $wt_mtx");
     }  
  } 

  # Arrange all uploaded files in hashes
  my %ali_files;
  my $upl_strs;
  my $ali_count = 0; #no of ali files
  my $seq_count = 0; #total no of seqs
  # Any uploaded files?
  if ( -e "$job_dir/upl_files.db" )
  {
     #Get uploaded files
     tie my %tie_hash, "DB_File", "$job_dir/upl_files.db", O_RDONLY
       or die "Cannot open tie to filetype DBM: $!";
     while ( my ($filen,$type) = each %tie_hash )
     {
        if ($type eq 'str') #save for use in sub cp_PBDs if needed
	{
           $upl_strs->{$filen} = 1;   
	}
	else
	{
           unless ( $type =~ /st$/ ) #skip str files
	   {
              if ( $filen =~ /^([\w.-]+)$/ ) { $filen = $1; }
              my $file_path = $upl_dir . '/' . $filen;
              my @type_split = split(/-/,$type);
	      $seq_count += $type_split[1];
	      $ali_files{$type_split[0]}{$file_path} = 1;
	      $ali_count++;
	      # remove structure entries if any
	      if ( $type =~ /stse$/ ) 
              {
	         my $str_entries = weed_strs($file_path,$type_split[2],$job_dir);
	         $seq_count = $seq_count - $str_entries;
              }
	   }   
	}   
     }
     untie %tie_hash;
  }

  my $str_dir;
  # if there are both uploaded strs and lib strs, gather them in a common dir
  if ( exists $str_segm{'upl'} && exists $str_segm{'lib'} )
  {
     $str_dir = cp_PDBs($str_segm_ref,$upl_dir,$static_dir,$job_dir,$upl_strs);
  }
  elsif ( exists $str_segm{'upl'} ) 
  { 
     $str_dir = 'upload';
  }
  else #only lib. copy to job dir (necessary for multiple entries of same pdb) 
  {
     $str_dir = cp_PDBs_noUpl($str_segm_ref,$static_dir,$job_dir); 
  }

  $str_segm_ref = OnePdbPerSegm($str_segm_ref,$job_dir,$str_dir);

  # create str-str top file
  my $output_strstr = "str-str_out.ali";
  strstr_topf($job_dir,$inputs,$static_dir,$str_segm_ref,$wt_mtx,'str-str.py',$output_strstr,$str_dir);

  # section below is mostly seq-seq stuff
  # add uploaded sequences to ali file hash
  if ( $inputs->{'upld_pseqs'} > 0 )
  {
     my $file_path = $job_dir . '/' . 'pasted_seqs.pir';
     $ali_files{'pir'}{$file_path} = 1;
     $ali_count++;
     $seq_count += $inputs->{'upld_pseqs'};
  }
  my $fin_alipath;      # path to final alignment file
  my $fin_aliformat;    # format of final ali file
  if ( $ali_count > 1 )   # if more than one ali file
  {
     #concatenate ali files
     my $fuse_file = $job_dir . '/' . 'fused_seqs.ali';
     $fin_aliformat = ali_fuser($q,$fuse_file,\%ali_files);
     $fin_alipath = $fuse_file;
  }
  else
  {
     if ( exists $ali_files{'pir'} )
     {
        $fin_aliformat = 'pir';
	my @file_ary = keys %{ $ali_files{'pir'} };
	$fin_alipath = shift ( @file_ary );
     }
     else
     {
        $fin_aliformat = 'fasta';
	my @file_ary = keys %{ $ali_files{'fasta'} }; 
	$fin_alipath = shift ( @file_ary );
     }
  }
  my $output_seqseq = "seq-seq_out.ali";

  if ( $adv == 1 )
  {
     # set 1D gap pens to their seq-seq values if Default
     if ( $inputs->{'1D_open_usr'} eq 'Default' )
     {
        $inputs->{'1D_open'} = $inputs->{'1D_open_sese'};
     }
     if ( $inputs->{'1D_elong_usr'} eq 'Default' )
     {
        $inputs->{'1D_elong'} = $inputs->{'1D_elong_sese'};
     }
  }
  else
  {
     # set 1Dgap pens to their seq-seq values
     $inputs->{'1D_open'} = $inputs->{'1D_open_sese'};
     $inputs->{'1D_elong'} = $inputs->{'1D_elong_sese'};
  }
  
  # create seq-seq top file
  sese_stse_topf($job_dir,$output_seqseq,$inputs,$static_dir,$fin_alipath,$fin_aliformat,'seq-seq',$seq_count,'sese','','');

  # section below takes care of step 2 (alignment of the 2 outputs from step 1)
  my $step2_str_dir;
  my $step2_input_ali = "str-seq_fuse.ali";
  my $step2_out_ali = "final_alignment.ali";
  
  # structure-sequence or profile profile in step 2?
  if ( $seq_count <= 100 || $str_count <= 100 )   # str-seq
  {
     if ( $str_count > 1 ) # more than one str => fitted PDBs are in job dir
     {
        $step2_str_dir = ".";
     }
     #only one str => stays in its original directory
     elsif ( exists $str_segm{'upl'} ) 
     { 
        $step2_str_dir = "upload";
     }
     else  
     { 
#       $step2_str_dir = $pdb_database; 
        $step2_str_dir = 'structures';
     }

     # set 1D gap pens to their str-seq values if default chosen
     if ( $adv == 1 )
     {
        if ( $inputs->{'1D_open_usr'} eq 'Default' )
        {
           $inputs->{'1D_open'} = $inputs->{'1D_open_stse'};
        }
        if ( $inputs->{'1D_elong_usr'} eq 'Default' )
        {
           $inputs->{'1D_elong'} = $inputs->{'1D_elong_stse'};
        }
     }
     else
     {
        $inputs->{'1D_open'} = $inputs->{'1D_open_stse'};
        $inputs->{'1D_elong'} = $inputs->{'1D_elong_stse'};
     }
 
     # create seq-str top file
     sese_stse_topf($job_dir,$step2_out_ali,$inputs,$static_dir,$step2_input_ali,'pir','final_alignment',$str_count,'stse',$step2_str_dir,'');
  }
  else  # profile-profile
  {
     # set 1D gap pens to their profile values if default chosen
     if ( $adv == 1 )
     {
        if ( $inputs->{'1D_open_usr'} eq 'Default' )
        {
           $inputs->{'1D_open'} = $inputs->{'1D_open_prof'};
        }
        if ( $inputs->{'1D_elong_usr'} eq 'Default' )
        {
           $inputs->{'1D_elong'} = $inputs->{'1D_elong_prof'};
        }
     }
     else
     {
        $inputs->{'1D_open'} = $inputs->{'1D_open_prof'};
        $inputs->{'1D_elong'} = $inputs->{'1D_elong_prof'};
     }
     # create profile-profile top file
#     profile_topf($job_dir,$step2_out_ali,$inputs,$static_dir,$step2_input_ali,'step2.py',$str_count);
     profile_topf($job_dir,$step2_out_ali,$inputs,$static_dir,$step2_input_ali,'final_alignment.py',$str_count);
  }
  # write relevant inputs to DBM file
  my $memo_inp;
  $memo_inp->{'email'} = $inputs->{'email'};
#  $memo_inp->{'fit_coord'} = $inputs->{'fit_coord'};
  $memo_inp->{'tool'} = 'str_seq';
  create_memo($memo_inp,$job_dir);
  return print_job_submission($self,$job, $inputs->{'email'});
}

# Main sub for one step seq-seq alignments
sub fp_onestep_sese
{
  my $self = shift;
  my $q = shift;
  my $job = shift;
  my $inputs = shift;
  my $entries = shift; #sequences, structures or both?
  my $adv = shift;
  my $conf_file = '/modbase5/home/salign/conf/salign.conf';
  # Read conf_file
  my $conf_ref = read_conf($conf_file);

  my $static_dir = $conf_ref->{'STATIC_DIR'};
  
  my $job_dir = ".";
  my $upl_dir = $job_dir . '/upload';

  if ( $adv == 1 )
  {
     if ( $inputs->{'1D_open_usr'} eq 'Default' )
     {
        $inputs->{'1D_open'} = $inputs->{'1D_open_sese'};
     }
     else { $inputs->{'1D_open'} = $inputs->{'1D_open_usr'}; }
     
     if ( $inputs->{'1D_elong_usr'} eq 'Default' )
     {
        $inputs->{'1D_elong'} = $inputs->{'1D_elong_sese'};
     }
     else { $inputs->{'1D_elong'} = $inputs->{'1D_elong_usr'}; }
  }
  else
  {
     $inputs->{'1D_open'} = $inputs->{'1D_open_sese'};
     $inputs->{'1D_elong'} = $inputs->{'1D_elong_sese'};
  }
  
  # get str segments if not only seqs
  my (%str_segm,$str_segm_ref,$str_count);
  unless ( $entries eq 'seqs' )  # structures exist
  {
     ($str_segm_ref,$str_count) = strstr_inputs($q,$inputs,$adv,'seq');
     %str_segm = %$str_segm_ref;
  }   
  
  # Arrange all uploaded files in hashes
  my %ali_files;
  my $upl_strs;
  my $ali_count = 0; #no of ali files
  my $seq_count = 0; #total no of seqs
  # Any uploaded files?
  if ( -e "$job_dir/upl_files.db" )
  {
     #Get uploaded files
     tie my %tie_hash, "DB_File", "$job_dir/upl_files.db", O_RDONLY
       or die "Cannot open tie to filetype DBM: $!";
     while ( my ($filen,$type) = each %tie_hash )
     {
        if ($type eq 'str') #save for use in sub cp_PBDs if needed
	{
           $upl_strs->{$filen} = 1;   
	}
	else
	{
           unless ( $type =~ /st$/ ) #skip str files
	   {
              if ( $filen =~ /^([\w.-]+)$/ ) { $filen = $1; }
              my $file_path = $upl_dir . '/' . $filen;
              my @type_split = split(/-/,$type);
	      $seq_count += $type_split[1];
	      $ali_files{$type_split[0]}{$file_path} = 1;
	      $ali_count++;
	      # remove structure entries if any
	      if ( $type =~ /stse$/ ) 
              {
	         my $str_entries = weed_strs($file_path,$type_split[2],$job_dir);
	         $seq_count = $seq_count - $str_entries;
              }
	   }   
	}   
     }
     untie %tie_hash;
  }

  # perform multiple tasks on ali files if not only strs
  my $fin_alipath;      # path to final alignment file
  my $fin_aliformat;    # format of final alignment file
  unless ( $entries eq 'strs' )
  {
     if ( $inputs->{'upld_pseqs'} > 0 )
     {
        my $file_path = $job_dir . '/' . 'pasted_seqs.pir';
        $ali_files{'pir'}{$file_path} = 1;
        $ali_count++;
        $seq_count += $inputs->{'upld_pseqs'};
     }
     
     if ( $ali_count > 1 )   # if more than one ali file
     {
        #concatenate ali files
        my $fuse_file = $job_dir . '/' . 'fused_seqs.ali';
        $fin_aliformat = ali_fuser($q,$fuse_file,\%ali_files);
        $fin_alipath = $fuse_file;
     }
     else
     {
        if ( exists $ali_files{'pir'} )
        {
           $fin_aliformat = 'pir';
   	   my @file_ary = keys %{ $ali_files{'pir'} };
	   $fin_alipath = shift ( @file_ary );
        }
        else
        {
           $fin_aliformat = 'fasta';
 	   my @file_ary = keys %{ $ali_files{'fasta'} }; 
	   $fin_alipath = shift ( @file_ary );
        }
     }
  }  
  else  # only structure files
  {
     $fin_alipath = '';
     $fin_aliformat = '';
  }
  
  my $output_file = "seq-seq_out.ali";
  my $topf_namebase = 'seq-seq';
  # create top files
  if ( $entries eq 'seqs' ) #only sequences
  {
     sese_stse_topf($job_dir,$output_file,$inputs,$static_dir,$fin_alipath,$fin_aliformat,$topf_namebase,$seq_count,'sese','','');
  }
  else  #structures and maybe sequences
  {
     my $str_dir;
     # if there are both uploaded strs and lib strs, gather them in a common dir
     if ( exists $str_segm{'upl'} && exists $str_segm{'lib'} )
     {
        $str_dir = cp_PDBs($str_segm_ref,$upl_dir,$static_dir,$job_dir,$upl_strs);
     }
     elsif ( exists $str_segm{'upl'} ) 
     { 
        $str_dir = 'upload';
     }
     else #only lib. copy to job dir (necessary for multiple entries of same pdb) 
     {
        $str_dir = cp_PDBs_noUpl($str_segm_ref,$static_dir,$job_dir); 
     }
     $seq_count += $str_count;
     $str_segm_ref = OnePdbPerSegm($str_segm_ref,$job_dir,$str_dir);
     sese_stse_topf($job_dir,$output_file,$inputs,$static_dir,$fin_alipath,$fin_aliformat,$topf_namebase,$seq_count,'sese_pdbs',$str_dir,$str_segm_ref);
  }

  # write relevant inputs to DBM file
  my $memo_inp;
  $memo_inp->{'email'} = $inputs->{'email'};
  $memo_inp->{'tool'} = '1s_sese';
  create_memo($memo_inp,$job_dir);
  return print_job_submission($self,$job, $inputs->{'email'});
}


# Main sub for two step seq-seq alignments
sub fp_twostep_sese
{
  my $self = shift;
  my $q = shift;
  my $job = shift;
  my $inputs = shift;
  my $adv = shift;
  my $conf_file = '/modbase5/home/salign/conf/salign.conf';
  # Read conf_file
  my $conf_ref = read_conf($conf_file);

  my $static_dir = $conf_ref->{'STATIC_DIR'};
  
  my $job_dir = '.';
  my $upl_dir = $job_dir . '/upload';

  if ( $adv == 1 )
  {
     # set 1D gap pens to their seq-seq values or usr value
     if ( $inputs->{'1D_open_usr'} eq 'Default' )
     {
        $inputs->{'1D_open'} = $inputs->{'1D_open_sese'};
     }
     else { $inputs->{'1D_open'} = $inputs->{'1D_open_usr'}; }
     
     if ( $inputs->{'1D_elong_usr'} eq 'Default' )
     {
        $inputs->{'1D_elong'} = $inputs->{'1D_elong_sese'};
     }
     else { $inputs->{'1D_elong'} = $inputs->{'1D_elong_usr'}; }
  }
  else
  {
     # set 1Dgap pens to their seq-seq values
     $inputs->{'1D_open'} = $inputs->{'1D_open_sese'};
     $inputs->{'1D_elong'} = $inputs->{'1D_elong_sese'};
  }

  # Arrange the two ali files in hash
  my %ali_files;
  if ( -e "$job_dir/upl_files.db" )
  {
     #Get uploaded ali files
     tie my %tie_hash, "DB_File", "$job_dir/upl_files.db", O_RDONLY
       or die "Cannot open tie to filetype DBM: $!";
     while ( my ($filen,$type) = each %tie_hash )
     {
        # skip uploaded str files (called 'used_strs' in SA_form.cgi)
        unless ( $type eq 'str' )
	{
           my $file_path = $upl_dir . '/' . $filen;
           my @type_split = split(/-/,$type); # [0] = type, [1] = no_of_entries
   	   $ali_files{$file_path}{'format'} = $type_split[0];
	   $ali_files{$file_path}{'length'} = $type_split[1];
        }
     }
     untie %tie_hash;
  }
  else { error($q,'No uploaded files for 2-step seq-seq'); }
  if ( $inputs->{'upld_pseqs'} > 0 )
  {
     my $file_path = 'pasted_seqs.pir';
     $ali_files{$file_path}{'format'} = 'pir';
     $ali_files{$file_path}{'length'} = $inputs->{'upld_pseqs'};
  }
  
  my $i = 1;
  my @seq_counts; #to store #of seqs for the ali files
  # create step 1 top files for both files
  foreach my $fin_alipath ( keys %ali_files )
  {
     my $fin_aliformat = $ali_files{$fin_alipath}{'format'};
     my $seq_count = $ali_files{$fin_alipath}{'length'};
     push @seq_counts, $seq_count;
     my $output_file = "seq-seq_out$i.ali";
     my $topf_namebase = "seq-seq$i";
     my $topf_name = $topf_namebase . '.py';
     # create top file for step 1
     if ( $seq_count <= 500 )  # dyn progr alignment 
     {
        sese_stse_topf($job_dir,$output_file,$inputs,$static_dir,$fin_alipath,$fin_aliformat,$topf_namebase,$seq_count,'sese','','');
     }
     else        # no realignment, but makes sure output format is PIR
     {
        faa2pir_topf($job_dir,$output_file,$static_dir,$fin_alipath,$fin_aliformat,$topf_name);  
     }
     $i++;
  }
  # create profile profile top file for step 2
  if ( $adv == 1 )
  {
     # set 1D gap pens to their prof-prof values or usr value
     if ( $inputs->{'1D_open_usr'} eq 'Default' )
     {
        $inputs->{'1D_open'} = $inputs->{'1D_open_prof'};
     }
     if ( $inputs->{'1D_elong_usr'} eq 'Default' )
     {
        $inputs->{'1D_elong'} = $inputs->{'1D_elong_prof'};
     }
  }
  else
  {
     # set 1Dgap pens to their prof-prof values
     $inputs->{'1D_open'} = $inputs->{'1D_open_prof'};
     $inputs->{'1D_elong'} = $inputs->{'1D_elong_prof'};
  }
  
  my $output_file = "final_alignment.ali";
  my $input_file = "prof_in.ali";
  my $topf_name = "profile.py";
  profile_topf($job_dir,$output_file,$inputs,$static_dir,$input_file,$topf_name,$seq_counts[0]);

  # write relevant inputs to DBM file
  my $memo_inp;
  $memo_inp->{'email'} = $inputs->{'email'};
  $memo_inp->{'tool'} = '2s_sese';
  create_memo($memo_inp,$job_dir);
  return print_job_submission($self,$job, $inputs->{'email'});
}


# main sub for advanced views
sub adv_views
{
  my $self = shift;
  my $q = shift;
  my $job = shift;
  my $inputs = shift;

  if ($inputs->{'tool'} eq "str_str_adv")
  {
     if ($inputs->{'sa_feature'} eq 'str_str') #str-str alignment
     {
        return fp_str_str($self,$q,$job,$inputs,1);
     }
     else  #only align sequences of structures
     {
        return fp_onestep_sese($self,$q,$job,$inputs,'strs',1);                  #
     }
  }
  elsif ($inputs->{'tool'} eq "str_seq_adv")
  {
     if ($inputs->{'sa_feature'} eq 'str_seq') #str-seq alignment
     {
        return fp_str_seq($self,$q,$job,$inputs,1);
     }
     else  #only align sequences 
     {
        return fp_onestep_sese($self,$q,$job,$inputs,'seqs_and_strs',1);         #
     }
  }
  elsif ($inputs->{'tool'} eq "sese_adv")
  {
     if ($inputs->{'sa_feature'} eq '2s_sese') 
     {
        return fp_twostep_sese($self,$q,$job,$inputs,1);
     }
     elsif ($inputs->{'sa_feature'} eq 'str_seq')
     {
        return fp_str_seq($self,$q,$job,$inputs,1);
     }
     else  # 1 step seq-seq
     {
        if ($inputs->{'structures'} == 1) 
	{ 
	   return fp_onestep_sese($self,$q,$job,$inputs,'seqs_and_strs',1);      #
	}
	else { return fp_onestep_sese($self,$q,$job,$inputs,'seqs',1); }         #
     } 
  }
  else
  {
     error($q,"Unidentified tool");
  }
}

# Concatenate many alignment files to one. also convert pir to fasta if needed
# Om ni vill ha kvar rad 2 i var entry kan ju chomp anvandas om ^> och sa skippas istallet hela $skip grejen
sub ali_fuser
{
  my $q = shift;
  my $fuse_file = shift;
  my $files = shift;
  my %ali_files = %$files;
  my $format = 'fasta';

  open FUSE_FILE, ">$fuse_file" or die "Cannot open $fuse_file: $!";
   
  if ( exists $ali_files{'pir'} )
  {
     # convert to fasta while copying if fasta files exist
     if ( exists $ali_files{'fasta'} )
     {
        foreach my $pir_file ( keys %{ $ali_files{'pir'} } )
        {
	   my $skip = 0;
           open FILE, "<$pir_file" or die "Cannot open $pir_file: $!";
           while (<FILE>)
	   {
	      if ( $skip == 1 )
	      {
	         $skip = 0;
		 next;
	      }	 
#	      s/\s+$//;
#	      s/\*$//;
              s/\*//;
	      if ( s/^>\w\w;/>/ )
	      {
	         print FUSE_FILE $_;
		 $skip = 1;
	      }
	      else { print FUSE_FILE $_; }
	   }
	   print FUSE_FILE "\n";
	   close FILE;
        }
     }
     # don't convert if only pir files
     else
     {
        foreach my $pir_file ( keys %{ $ali_files{'pir'} } )
        {
           open FILE, "<$pir_file" or die "Cannot open $pir_file: $!";
	   while (<FILE>)
	   {
	      print FUSE_FILE $_;
	   }
	   print FUSE_FILE "\n";
	   close FILE;
        }
	$format = 'pir';
     }
  }
  if ( exists $ali_files{'fasta'} )
  {
     foreach my $fasta_file ( keys %{ $ali_files{'fasta'} } )
     {
        open FILE, "<$fasta_file" or die "Cannot open $fasta_file: $!";
        while (<FILE>)
	{
	   print FUSE_FILE $_;
	}
	print FUSE_FILE "\n";
	close FILE;
     }
  }
  close FUSE_FILE;
  return($format);
}
 
# erase all structure entries from an ali file containing
# both structures and sequences. returns number of strs weeded
sub weed_strs
{
  my $ali_file = shift;
  my $conc_linenos = shift;
  my $job_dir = shift;
  my $tmp_file = $job_dir . '/weeder.tmp';
 
  # retrieve all str line numbers and store as keys in a hash
  my @split_linenos = split(/_/,$conc_linenos);
  my $weeded_strs = $#split_linenos + 1;
  my %linenos;
  foreach my $line_no ( @split_linenos )
  {
     $linenos{$line_no} = 1;
  }   
  open(ALI_FILE, "<$ali_file") or die "Cannot open $ali_file: $!";
  open(TMP_FILE, ">$tmp_file")  or die "Cannot open $tmp_file: $!";
  # copy ali file to temp file, skipping str entries
  my $skip = 0;
  while (<ALI_FILE>)
  {
     if ( $skip == 1 )
     {
        if ( /^>/ ) { $skip = 0; }
	else        { next;      }
     }	
     my $next_line = $. + 1;
     if ( exists $linenos{$next_line} )
     {
        $skip = 1;
	next;
     }
     print TMP_FILE $_;
  }
  close TMP_FILE;
  close ALI_FILE;
#  system ("mv","$tmp_file","$ali_file");

# Check filename for dangerous characters
#  if ( $ali_file =~ /^([\w.-]+)$/ ) { $ali_file = $1; }
#    else {die "Can't untaint input ali file";}
  move("$tmp_file", "$ali_file")
    or die "move failed:$ali_file $tmp_file $! ";
  return($weeded_strs);
}  

# check and process str-str form inputs
sub strstr_inputs
{
  my $q = shift;
  my $inputs_ref = shift;
  my $adv = shift;
  my $feat = shift; # feature of PDB that will be used - str or seq
  my %inputs = %$inputs_ref;
  my %str_segm;
  my $str_count = 0;
  
  # create hash of all pdb segments
  foreach my $input ( keys %inputs )
  {
     my $structure = $input;
     # Segments from uploaded files
     if ( $structure =~ s/^uplsegm_// )
     {
        my $orign = $structure;
	$structure =~ s/\.pdb$//;
	$structure =~ s/\.ent$//;
        my @segments = split( /\r\n/, $inputs{$input} );
	foreach my $i ( 0 .. $#segments )
	{
	   my $segment = $segments[$i] . ":";
	   my @delim = split( /(:)/, $segment );
	   unless ($#delim == 7)
	   {
	     error($q,"Incorrect input format: structure segments");
	   }
	   my $start = $delim[0] . $delim[1] . $delim[2];
	   my $end = $delim[4] . $delim[5] . $delim[6];
	   push @{ $str_segm{'upl'}{$structure}{'start'} }, $start; 
	   push @{ $str_segm{'upl'}{$structure}{'end'} }, $end; 
	   push @{ $str_segm{'upl'}{$structure}{'st_ch'} }, $delim[2]; 
	   $str_count++;
	}
        $str_segm{'upl'}{$structure}{'orign'} = $orign;
     }
     # Segments from library files
     elsif ( $structure =~ s/^libsegm_// )
     {
        my @segments = split( /\r\n/, $inputs{$input} );
	foreach my $i ( 0 .. $#segments )
	{
	   my $segment = $segments[$i] . ":";
	   my @delim = split( /(:)/, $segment );
	   unless ($#delim == 7)
	   {
	     error($q,"Incorrect input format: structure segments");
	   }
	   my $start = $delim[0] . $delim[1] . $delim[2];
	   my $end = $delim[4] . $delim[5] . $delim[6];
	   push @{ $str_segm{'lib'}{"\L$structure"}{'start'} }, $start; 
	   push @{ $str_segm{'lib'}{"\L$structure"}{'end'} }, $end; 
	   push @{ $str_segm{'lib'}{"\L$structure"}{'st_ch'} }, $delim[2]; 
	   $str_count++;
	}
     }
  }   
  if ( $adv == 1 )
  {
     unless ($inputs{'1D_open'} ne "")
     {
        error($q,"You must specify a 1D gap open penalty");
     }
     unless ($inputs{'1D_elong'} ne "")
     {
        error($q,"You must specify a 1D gap elongation penalty");
     }
     if ( $feat eq 'str' )
     {
        unless ($inputs{'3D_open'} ne "")
        {
           error($q,"You must specify a 3D gap open penalty");
        }
        unless ($inputs{'3D_elong'} ne "")
        {
           error($q,"You must specify a 3D gap elongation penalty");
        }
        foreach my $i ( 1 .. 6 )
        {
           unless ($inputs{"fw_$i"} ne "")
           {
              error($q,"You must specify all feature weights");
           }
        }   
        if ($inputs{'fw_6'} != 0)
        {
           unless ($inputs{'weight_mtx'} ne "")
           {
              error($q,"You must specify a weight matrix to upload when feature weight 6 != 0");
           }
        }
        unless ($inputs{'RMS_cutoff'} ne "")  
        {     
           error($q,"You must specify an RMS cutoff");  
        }
     }	
  }   
  return(\%str_segm,$str_count); 
}


# copy PDB files from PDB library and $upl_dir to a common directory
# perhaps call chk_dir_size here?
sub cp_PDBs
{
  my $str_segm_ref = shift;
  my $upl_dir = shift;
  my $static_dir = shift;
  my $job_dir = shift;
  my $upl_strs_ref = shift;
  my %str_segm = %$str_segm_ref;
  my %upl_strs = %$upl_strs_ref;
  my $common_dir = $job_dir . '/structures';
  my $pdb_dir = $pdb_database;

  mkdir $common_dir
    or die "Can't create sub directory $common_dir: $!\n";

  my $pdb_dbm = "$static_dir/lib_pdbs.db";  
  tie my %pdb_hash, "DB_File", $pdb_dbm, O_RDONLY  
    or die "Cannot open tie to PDB DBM: $!"; 

  foreach my $lib_str ( keys %{ $str_segm{'lib'} } )
  {
     my @possible_filens = ( "pdb$lib_str.ent", "pdb$lib_str",
                            "$lib_str.ent", "$lib_str"        );
     foreach my $filen ( @possible_filens )
     {
        if ( exists $pdb_hash{$filen} )
	{  
#           system ("cp","$pdb_dir/$filen","$common_dir/$filen");
           copy("$pdb_dir/$filen", "$common_dir/$lib_str.ent")
             or die "copy failed: $!";
	   last;
	}   
     }
  }   
  untie %pdb_hash;
  
  foreach my $filen ( keys %upl_strs )
  {
#     system ("mv","$upl_dir/$filen","$common_dir/$filen");
     move("$upl_dir/$filen","$common_dir/$filen")
       or die "move failed: $!";
  }
  return('structures');
}
 
# copy PDB files from PDB library to job dir
sub cp_PDBs_noUpl
{
  my $str_segm_ref = shift;
  my $static_dir = shift;
  my $job_dir = shift;
  my %str_segm = %$str_segm_ref;
  my $common_dir = $job_dir . '/structures';
  my $pdb_dir = $pdb_database;

  mkdir $common_dir
    or die "Can't create sub directory $common_dir: $!\n";

  my $pdb_dbm = "$static_dir/lib_pdbs.db";  
  tie my %pdb_hash, "DB_File", $pdb_dbm, O_RDONLY  
    or die "Cannot open tie to PDB DBM: $!"; 

  foreach my $lib_str ( keys %{ $str_segm{'lib'} } )
  {
     my @possible_filens = ( "pdb$lib_str.ent", "pdb$lib_str",
                            "$lib_str.ent", "$lib_str"        );
     foreach my $filen ( @possible_filens )
     {
        if ( exists $pdb_hash{$filen} )
	{  
#           system ("cp","$pdb_dir/$filen","$common_dir/$filen");
           copy("$pdb_dir/$filen", "$common_dir/$lib_str.ent")
             or die "copy failed: $!";
	   last;
	}   
     }
  }   
  untie %pdb_hash;
  return('structures');
}


# go through structure segments and check for multiple segments of the same pdb.
# if found, make one copy of pdb for each segment, named as orig file, but
# appended with _1, _2 and so on. hence also converts arrays to scalars.
sub OnePdbPerSegm
{
  my $str_segm_ref = shift;
  my $job_dir = shift;
  my $str_dir = shift;
  my %str_segm = %$str_segm_ref;
  my %mod_str_segm = { %str_segm };

  $str_dir = $job_dir . '/' . $str_dir;

  foreach my $str ( keys %{ $str_segm{'upl'} } )
  {
     $mod_str_segm{'upl'}{$str}{'start'} =  $str_segm{'upl'}{$str}{'start'}[0] ;
     $mod_str_segm{'upl'}{$str}{'end'} =  $str_segm{'upl'}{$str}{'end'}[0] ;
     $mod_str_segm{'upl'}{$str}{'st_ch'} =  $str_segm{'upl'}{$str}{'st_ch'}[0] ;

     if ( $#{ $str_segm{'upl'}{$str}{'start'} } > 0 )
     {
        foreach my $i ( 1 .. $#{ $str_segm{'upl'}{$str}{'start'} } )
        {
            my $new_filen = change_name1($str_segm{'upl'}{$str}{'orign'},$str_dir,$i,1000); 
            copy("$str_dir/$str_segm{'upl'}{$str}{'orign'}", "$str_dir/$new_filen")
             or die "copy failed: $!";
            $new_filen =~ s/\.pdb$//;
	    $new_filen =~ s/\.ent$//;
            $mod_str_segm{'upl'}{$new_filen}{'start'} = $str_segm{'upl'}{$str}{'start'}[$i] ;
            $mod_str_segm{'upl'}{$new_filen}{'end'} =  $str_segm{'upl'}{$str}{'end'}[$i] ;
            $mod_str_segm{'upl'}{$new_filen}{'st_ch'} =  $str_segm{'upl'}{$str}{'st_ch'}[$i] ;
        }
     }
  }
  foreach my $str ( keys %{ $str_segm{'lib'} } )
  {
        $mod_str_segm{'lib'}{$str}{'start'} =  $str_segm{'lib'}{$str}{'start'}[0] ;
        $mod_str_segm{'lib'}{$str}{'end'} =   $str_segm{'lib'}{$str}{'end'}[0]  ;
        $mod_str_segm{'lib'}{$str}{'st_ch'} =  $str_segm{'lib'}{$str}{'st_ch'}[0]  ;

     if ( $#{ $str_segm{'lib'}{$str}{'start'} } > 0 )
     {
        foreach my $i ( 1 .. $#{ $str_segm{'lib'}{$str}{'start'} } )
        {
            my $new_filen = change_name1("$str.ent",$str_dir,$i,1000); 
            copy("$str_dir/$str.ent", "$str_dir/$new_filen")
             or die "copy failed: $!";
	    $new_filen =~ s/\.ent$//;
            $mod_str_segm{'lib'}{$new_filen}{'start'} =  $str_segm{'lib'}{$str}{'start'}[$i]  ;
            $mod_str_segm{'lib'}{$new_filen}{'end'} =  $str_segm{'lib'}{$str}{'end'}[$i] ;
            $mod_str_segm{'lib'}{$new_filen}{'st_ch'} =  $str_segm{'lib'}{$str}{'st_ch'}[$i]  ;
        }
     }
  }
  return(\%mod_str_segm);
}

     
# upload file
sub fp_file_upload
{
  my $q = shift;
  my $upl_dir = shift;
  my $buffer_size = shift;
  my $file = shift;
  my $max_open = shift;
  # Extract and security check file name
  my $filen = $q->param($file);
  $filen = filen_fix( $q,$filen );
  if ( -e "$upl_dir/$filen" )
  {
     $filen = change_name($q,$filen,$upl_dir,$max_open);
  }
  
  # Get file handle 
  my $fh = $q->upload($file) or die "Can't upload $filen: $!";
  my $buffer = "";
  open(UPLOAD_OUT, ">$upl_dir/$filen") or die "Cannot open $filen: $!";
  # Write contents of upload file to $filen
  while( read($fh,$buffer,$buffer_size) ) {print UPLOAD_OUT "$buffer";}
  close UPLOAD_OUT;
  
  return($filen);
}


# change file name until uniqueness or limit is reached
sub change_name
{
  my ($q,$filen,$upl_dir,$max_open) = @_; 
  my $tempn;
  foreach my $i ( 1 .. $max_open ) 
  { 
     my @filename = split( /\./,$filen );
     $filename[0] = $filename[0] . "_" . $i;
     $tempn = join( ".",@filename );
     unless ( -e "$upl_dir/$tempn" )
     {
        $filen = $tempn;
        last;
     }
  }
  unless ( $filen eq $tempn )
  {
     error($q,"No unique file name found");
  }	
  return($filen);
}

# change file name until uniqueness or limit is reached
sub change_name1
{
  my ($filen,$dir,$start,$max_open) = @_; 
  my $tempn;
  foreach my $i ( $start .. $max_open ) 
  { 
     my @filename = split( /\./,$filen );
     $filename[0] = $filename[0] . "_" . $i;
     $tempn = join( ".",@filename );
     unless ( -e "$dir/$tempn" )
     {
        $filen = $tempn;
        last;
     }
  }
  return($filen);
}

# create a memo file storing the user inputs in DBM format
sub create_memo
{
  my $memo_inp_ref = shift;
  my $job_dir = shift;
  my $memo_name = "inputs.db";  
   
  # Create DBM file and let it store the user input
  my %memo_inp;
  tie(%memo_inp, "DB_File", "$job_dir/$memo_name", O_CREAT|O_WRONLY) or die "Cannot open tie to $memo_name: $!";
  %memo_inp = %$memo_inp_ref;
  untie %memo_inp;
}

# Create top file for str-str
sub strstr_topf
{
  my $job_dir = shift;
  my $inputs = shift;
  my $static_dir = shift;
  my $str_segm_ref = shift;
  my $wt_mtx = shift;
  my $topf_name = shift;
  my $output_ali = shift;
  my $str_dir = shift;
  $str_dir .= "/";
  my %str_segm = %$str_segm_ref;

  # Set variables for incorporation in top file      
  my $rms_cutoff = $inputs->{'RMS_cutoff'};     
  my $ogp_3d = $inputs->{'3D_open'};
  my $egp_3d = $inputs->{'3D_elong'};
  my $ogp_3d_roof = $ogp_3d + 3;
  my $egp_3d_roof = $egp_3d + 3;

  # structure directory and structure segments below
  #  $str_dir = "'$str_dir'";
  my $segm_count = 0;
  my $tf_str_segm = "for (_code, _start, _end, _code_ap) in (";
  my @single_segm;
  # set segments for specified library structures
  if ( exists $str_segm{'lib'} )
  {
     foreach my $lib_str ( keys %{ $str_segm{'lib'} } )
     {
=pod
	foreach my $i ( 0 .. $#{ $str_segm{'lib'}{$lib_str}{'start'} } )
        {
	   if ($segm_count == 0)
	   {
              $tf_str_segm .= "('$lib_str', ";
	      $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'start'}[$i]', ";
	      $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'end'}[$i]', ";
	      $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'st_ch'}[$i]";
	      $tf_str_segm .= "_$i')";
	      push (@single_segm, $lib_str, 
	            $str_segm{'lib'}{$lib_str}{'start'}[$i],
		    $str_segm{'lib'}{$lib_str}{'end'}[$i],
		    "$str_segm{'lib'}{$lib_str}{'st_ch'}[$i]" . "_$i");
	   }
	   else
	   {
	      $tf_str_segm .= ", ('$lib_str', ";
              $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'start'}[$i]', ";
	      $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'end'}[$i]', ";
	      $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'st_ch'}[$i]";
	      $tf_str_segm .= "_$i')";
           }
	   $segm_count++;
        }
=cut
	   if ($segm_count == 0)
	   {
              $tf_str_segm .= "('$lib_str', ";
	      $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'start'}', ";
	      $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'end'}', ";
	      $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'st_ch'}')";
	      push (@single_segm, $lib_str, 
	            $str_segm{'lib'}{$lib_str}{'start'},
		    $str_segm{'lib'}{$lib_str}{'end'},
		    $str_segm{'lib'}{$lib_str}{'st_ch'});
	   }
	   else
	   {
	      $tf_str_segm .= ", ('$lib_str', ";
              $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'start'}', ";
	      $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'end'}', ";
	      $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'st_ch'}')";
           }
	   $segm_count++;
     }
  }

  # set segments for uploaded structures
  if ( exists $str_segm{'upl'} )
  {
     foreach my $upl_str ( keys %{ $str_segm{'upl'} } )
     {
=pod
	foreach my $i ( 0 .. $#{ $str_segm{'upl'}{$upl_str}{'start'} } )
        {
	   if ($segm_count == 0)
	   {
              $tf_str_segm .= "('$upl_str', ";
	      $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'start'}[$i]', ";
	      $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'end'}[$i]', ";
	      $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'st_ch'}[$i]";
	      $tf_str_segm .= "_$i')";
	      push (@single_segm, $upl_str, 
	            $str_segm{'upl'}{$upl_str}{'start'}[$i],
		    $str_segm{'upl'}{$upl_str}{'end'}[$i],
		    "$str_segm{'upl'}{$upl_str}{'st_ch'}[$i]" . "_$i");
	   }
	   else
	   {
	      $tf_str_segm .= ", ('$upl_str', ";
              $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'start'}[$i]', ";
	      $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'end'}[$i]', ";
	      $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'st_ch'}[$i]";
	      $tf_str_segm .= "_$i')";
           }
	   $segm_count++;
        }
=cut    
           if ($segm_count == 0)
	   {
              $tf_str_segm .= "('$upl_str', ";
	      $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'start'}', ";
	      $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'end'}', ";
	      $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'st_ch'}')";
	      push (@single_segm, $upl_str, 
	            $str_segm{'upl'}{$upl_str}{'start'},
		    $str_segm{'upl'}{$upl_str}{'end'},
		    $str_segm{'upl'}{$upl_str}{'st_ch'});
	   }
	   else
	   {
	      $tf_str_segm .= ", ('$upl_str', ";
              $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'start'}', ";
	      $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'end'}', ";
	      $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'st_ch'}')";
           }
	   $segm_count++;
     }
  }

  if ($segm_count > 1) # Loop if more than one segment.
  {
     $tf_str_segm .="): \n";
     $tf_str_segm .="       mdl = model(env, file=_code, model_segment=(_start, _end))\n";
     $tf_str_segm .="       aln.append_model(mdl, atom_files=_code, align_codes=_code+_code_ap)";
  }
  else # Only one segment. Dont do loop.
  {
     $tf_str_segm = "mdl = model(env, file='$single_segm[0]', model_segment=(";
     $tf_str_segm .= "'$single_segm[1]', '$single_segm[2]'))\n";
     $tf_str_segm .= "    aln.append_model(mdl, atom_files='$single_segm[0]', ";
     $tf_str_segm .= "align_codes='$single_segm[0]$single_segm[3]')";
  }
  
  my $ali_type;
  if ( $inputs->{'align_type'} eq 'automatic' )
  {
     if ( $segm_count <= 30 ) { $ali_type = "'tree'"; }
     else { $ali_type = "'progressive'"; }
  }
  else { $ali_type = "'" . $inputs->{'align_type'} . "'"; }
  
  my $ogp_1d = $inputs->{'1D_open'};
  my $egp_1d = $inputs->{'1D_elong'};
  my $ogp_1d_step = -($ogp_1d/5);
  my $egp_1d_step = -($egp_1d/5);
#  $output_ali = "'$output_ali'";
  
  my $max_gap = $inputs->{'max_gap'};
  my $overhangs = $inputs->{'overhangs'};
  my $fit = $inputs->{'fit'};
  my $improve = $inputs->{'improve'};
  my $write_whole = $inputs->{'write_whole'};
  my $gap_gap_score = $inputs->{'gap-gap_score'};
  my $gap_res_score = $inputs->{'gap-res_score'};
  my $dnd_file;
  if ( $ali_type eq "'tree'" )
  {
     $dnd_file = "dendrogram_file='str-str.tree',";
  }
  else { $dnd_file = ''; }
  
  my $weight_mtx;
  my $feat_weights  = $inputs->{'fw_1'} . ", " . $inputs->{'fw_2'} . ", ";
     $feat_weights .= $inputs->{'fw_3'} . ", " . $inputs->{'fw_4'} . ", ";
     $feat_weights .= $inputs->{'fw_5'} . ", ";

  # create top file. type dependent on whether weight mtx has been uploaded or not.
  my $top_file = $job_dir . '/' . $topf_name;
  sysopen(TOP_OUT, $top_file, O_WRONLY | O_CREAT | O_EXCL)
    or die "Can't open top file $top_file to create: $!";

  if ($inputs->{'weight_mtx'} eq "") {    # ext weight mtx not uploaded
     $weight_mtx = "";
     $feat_weights .= $inputs->{'fw_6'};
     # Open iterative template top file
     open TOP_IN, "<$static_dir/salign_mix_1f.py" or die "Can't open template top file: $!";
  }  
  else {                                  # ext weight mtx uploaded
     $weight_mtx = "input_weights_file='upload/$wt_mtx',";
     $feat_weights .= "1";
     # Open oldschool template top file
     open TOP_IN, "<$static_dir/st-st_tmpl.py" or die "Can't open template top file: $!";
  }

  # Go through template top file, modify key words and print to new top file
  while( my $line = <TOP_IN> )
  {
     $line =~ s/HB_RMS_CUTOFF_HB/$rms_cutoff/g;
     $line =~ s/HB_OGP_3D_HB/$ogp_3d/g;
     $line =~ s/HB_EGP_3D_HB/$egp_3d/g;
     $line =~ s/HB_OGP_3D_ROOF_HB/$ogp_3d_roof/g;
     $line =~ s/HB_EGP_3D_ROOF_HB/$egp_3d_roof/g;
     $line =~ s/HB_WEIGHT_MTX_HB/$weight_mtx/g;
     $line =~ s/HB_STR_DIR_HB/$str_dir/g;
     $line =~ s/HB_SALIGN_STR_SEGM_HB/$tf_str_segm/g;
     $line =~ s/HB_ALIGN_TYPE_HB/$ali_type/g;
     $line =~ s/HB_FEAT_WEIGHTS_HB/$feat_weights/g;
     $line =~ s/HB_OGP_1D_HB/$ogp_1d/g;
     $line =~ s/HB_EGP_1D_HB/$egp_1d/g;
     $line =~ s/HB_OGP_1D_STEP_HB/$ogp_1d_step/g;
     $line =~ s/HB_EGP_1D_STEP_HB/$egp_1d_step/g;
     $line =~ s/HB_ALI_OUT_HB/$output_ali/g;
     $line =~ s/HB_MAX_GAP_HB/$max_gap/g;
     $line =~ s/HB_OVERHANGS_HB/$overhangs/g;
     $line =~ s/HB_FIT_HB/$fit/g;
     $line =~ s/HB_IMPROVE_HB/$improve/g;
     $line =~ s/HB_WHOLE_PDB_HB/$write_whole/g;
     $line =~ s/HB_GAP_GAP_HB/$gap_gap_score/g;
     $line =~ s/HB_GAP_RES_HB/$gap_res_score/g;
     $line =~ s/HB_DND_FILE_HB/$dnd_file/g;
     print TOP_OUT $line;
  }   
       
  close TOP_IN;
  close TOP_OUT;
}

 
# Create top file for seq-seq and str-seq
sub sese_stse_topf
{
  my $job_dir = shift;
  my $output_file = shift;
  my $inputs = shift;
  my $static_dir = shift;
  my $fin_alipath = shift;
  my $fin_aliformat = shift;
  my $topf_namebase = shift;
  my $seq_count = shift;    #no of entries; total for sese, 
                            #first block (strs) for stse
  my $top_type = shift;     #determines if seq-seq or str-seq topf
  my $str_dir = shift;      #pdb directory
  my $str_segm_ref = shift; #ref to hash of str segments if any exist. for sese 
  
  # Set variables for incorporation in top file      
  my ($ali_type,$gap_fctn,$gap_pen_2D,$align_block);
  my ($max_gap,$dnd_file);
  my $tf_str_segm = '';
  my $topf_name = $topf_namebase . '.py';
 
  # set vars specific for st-se or se-se
  if ( $top_type eq 'stse' )
  {
     $ali_type = "'pairwise'";
     $str_dir = "env.io.atom_files_directory=" . "'" . $str_dir . "'";
     $gap_fctn = "gap_function=True,";
     $gap_pen_2D = "gap_penalties_2d=(";
     $gap_pen_2D .= $inputs->{'2D_1'} . ', ' . $inputs->{'2D_2'} . ', ';
     $gap_pen_2D .= $inputs->{'2D_3'} . ', ' . $inputs->{'2D_4'} . ', ';
     $gap_pen_2D .= $inputs->{'2D_5'} . ', ' . $inputs->{'2D_6'} . ', ';
     $gap_pen_2D .= $inputs->{'2D_7'} . ', ' . $inputs->{'2D_8'} . ', ';
     $gap_pen_2D .= $inputs->{'2D_9'} . '),';
     $align_block = "align_block=$seq_count,";
     $dnd_file = '';
     $max_gap = "max_gap_length=$inputs->{'max_gap'}" . ',';
  }
  else  # seq-seq
  { 
     if ( $top_type eq 'sese_pdbs' ) # PDBs included that must be parsed for seqs
     {
        $str_dir = "env.io.atom_files_directory=" . "'" . $str_dir . "'";
        my %str_segm = %$str_segm_ref;
        $tf_str_segm .= "for (_code, _start, _end, _code_ap) in (";
        my $segm_count = 0;
        my @single_segm;
        # set segments for specified library structures
        if ( exists $str_segm{'lib'} )
        {
           foreach my $lib_str ( keys %{ $str_segm{'lib'} } )
           {
=pod
   	      foreach my $i ( 0 .. $#{ $str_segm{'lib'}{$lib_str}{'start'} } )
              {
	         if ( $segm_count == 0 )
	         {
                    $tf_str_segm .= "('$lib_str', ";
	            $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'start'}[$i]', ";
		    $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'end'}[$i]', ";
		    $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'st_ch'}[$i]";
		    $tf_str_segm .= "_$i')";
                    push (@single_segm, $lib_str, 
	                  $str_segm{'lib'}{$lib_str}{'start'}[$i],
		          $str_segm{'lib'}{$lib_str}{'end'}[$i],
		          "$str_segm{'lib'}{$lib_str}{'st_ch'}[$i]" . "_$i");
	         }
	         else
	         {
                    $tf_str_segm .= ", ('$lib_str', ";
	            $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'start'}[$i]', ";
		    $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'end'}[$i]', ";
		    $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'st_ch'}[$i]";
		    $tf_str_segm .= "_$i')";
                 }
		 $segm_count++;
              }
=cut
	         if ( $segm_count == 0 )
	         {
                    $tf_str_segm .= "('$lib_str', ";
	            $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'start'}', ";
		    $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'end'}', ";
		    $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'st_ch'}')";
                    push (@single_segm, $lib_str, 
	                  $str_segm{'lib'}{$lib_str}{'start'},
		          $str_segm{'lib'}{$lib_str}{'end'},
		          $str_segm{'lib'}{$lib_str}{'st_ch'});
	         }
	         else
	         {
                    $tf_str_segm .= ", ('$lib_str', ";
	            $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'start'}', ";
		    $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'end'}', ";
		    $tf_str_segm .= "'$str_segm{'lib'}{$lib_str}{'st_ch'}')";
                 }
		 $segm_count++;
           }
        }
        # set segments for uploaded structures
        if ( exists $str_segm{'upl'} )
        {
           foreach my $upl_str ( keys %{ $str_segm{'upl'} } )
           {
=pod
              foreach my $i ( 0 .. $#{ $str_segm{'upl'}{$upl_str}{'start'} } )
              {
	         if ( $segm_count == 0 )
	         {
                    $tf_str_segm .= "('$upl_str', ";
	            $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'start'}[$i]', ";
		    $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'end'}[$i]', ";
		    $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'st_ch'}[$i]";
		    $tf_str_segm .= "_$i')";
                    push (@single_segm, $upl_str, 
	                  $str_segm{'upl'}{$upl_str}{'start'}[$i],
		          $str_segm{'upl'}{$upl_str}{'end'}[$i],
		          "$str_segm{'upl'}{$upl_str}{'st_ch'}[$i]" . "_$i");
	         }
	         else
	         {
                    $tf_str_segm .= ", ('$upl_str', ";
	            $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'start'}[$i]', ";
		    $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'end'}[$i]', ";
		    $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'st_ch'}[$i]";
		    $tf_str_segm .= "_$i')";
                 }
		 $segm_count++;
              }
=cut
	         if ( $segm_count == 0 )
	         {
                    $tf_str_segm .= "('$upl_str', ";
	            $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'start'}', ";
		    $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'end'}', ";
		    $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'st_ch'}')";
                    push (@single_segm, $upl_str, 
	                  $str_segm{'upl'}{$upl_str}{'start'},
		          $str_segm{'upl'}{$upl_str}{'end'},
		          $str_segm{'upl'}{$upl_str}{'st_ch'});
	         }
	         else
	         {
                    $tf_str_segm .= ", ('$upl_str', ";
	            $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'start'}', ";
		    $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'end'}', ";
		    $tf_str_segm .= "'$str_segm{'upl'}{$upl_str}{'st_ch'}')";
                 }
		 $segm_count++;
           }
        }
	if ($segm_count > 1) # Loop if more than one segment.
        {
           $tf_str_segm .="): \n";
           $tf_str_segm .="       mdl = model(env, file=_code, model_segment=(_start, _end))\n";
           $tf_str_segm .="       aln.append_model(mdl, atom_files=_code, align_codes=_code+_code_ap)";
        }
        else # Only one segment. Dont do loop.
        {
           $tf_str_segm = "mdl = model(env, file='$single_segm[0]', model_segment=(";
           $tf_str_segm .= "'$single_segm[1]', '$single_segm[2]'))\n";
           $tf_str_segm .= "    aln.append_model(mdl, atom_files='$single_segm[0]', ";
           $tf_str_segm .= "align_codes='$single_segm[0]$single_segm[3]')";
        }
     }

     else # All ali entries, no need to parse PDBs for seqs
     {
        $str_dir  = '';
     }
     if ( $inputs->{'align_type'} eq 'automatic' )
     {
        if ( $seq_count <= 30 ) { $ali_type = "'tree'"; }
        else { $ali_type = "'progressive'"; }
     }
     else { $ali_type = "'" . $inputs->{'align_type'} . "'"; }
     if ( $ali_type eq "'tree'" && $seq_count > 2 )
     {
	my $dnd_name = $topf_namebase . '.tree';
        $dnd_file = "dendrogram_file='$dnd_name',";
     }
     else { $dnd_file = ''; }
     $gap_fctn   = '';
     $gap_pen_2D = '';
     $align_block = '';
     $max_gap = '';
  }
  # common vars for str-seq and seq-seq
  my $gap_pen_1D = $inputs->{'1D_open'} . ", " . $inputs->{'1D_elong'};     
  my $output_ali = "'$output_file'";
  my $read_ali_line;
  unless ( $fin_alipath eq '' )
  {
     $read_ali_line  = "aln = alignment(env, file= '$fin_alipath', ";
     $read_ali_line .= "align_codes='all', ";
     $read_ali_line .= "alignment_format= '$fin_aliformat')";
  }
  else
  {
     $read_ali_line = "aln = alignment(env)";
  }
  
  my $overhangs = $inputs->{'overhangs'};
  my $improve = $inputs->{'improve'};
  my $gap_gap_score = $inputs->{'gap-gap_score'};
  my $gap_res_score = $inputs->{'gap-res_score'};

  # create top file
  my $top_file = $job_dir . '/' . $topf_name;
  sysopen(TOP_OUT, $top_file, O_WRONLY | O_CREAT | O_EXCL)
    or die "Can't open top file to create: $!";
  # Open template top file
  open TOP_IN, "<$static_dir/sese_stse_tmpl.py" 
    or die "Can't open template top file: $!";
  # Go through template top file, modify key words and print to new top file
  while( my $line = <TOP_IN> )
  {
     $line =~ s/HB_STR_DIR_HB/$str_dir/g;
     $line =~ s/HB_READ_ALI_HB/$read_ali_line/g;
     $line =~ s/HB_SALIGN_STR_SEGM_HB/$tf_str_segm/g;
     $line =~ s/HB_ALIGN_TYPE_HB/$ali_type/g;
     $line =~ s/HB_ALIGN_BLOCK_HB/$align_block/g;
     $line =~ s/HB_GAP_FCTN_HB/$gap_fctn/g;
     $line =~ s/HB_GAP_PEN_1D_HB/$gap_pen_1D/g;
     $line =~ s/HB_GAP_PEN_2D_HB/$gap_pen_2D/g;
     $line =~ s/HB_ALI_OUT_HB/$output_ali/g;
     $line =~ s/HB_MAX_GAP_HB/$max_gap/g;
     $line =~ s/HB_OVERHANGS_HB/$overhangs/g;
     $line =~ s/HB_IMPROVE_HB/$improve/g;
     $line =~ s/HB_GAP_GAP_HB/$gap_gap_score/g;
     $line =~ s/HB_GAP_RES_HB/$gap_res_score/g;
     $line =~ s/HB_DND_FILE_HB/$dnd_file/g;
     print TOP_OUT $line;
  }   
  close TOP_IN;
  close TOP_OUT;
}

# Create top file for profile-profile alignment
sub profile_topf
{
  my $job_dir = shift;
  my $output_ali = shift;
  my $inputs = shift;
  my $static_dir = shift;
  my $input_ali = shift;
  my $topf_name = shift;
  my $seq_count_1 = shift;

  # Set variables for incorporation in top file      
  my $gap_pen_1D = $inputs->{'1D_open'} . ", " . $inputs->{'1D_elong'};     

  # create top file
  my $top_file = $job_dir . '/' . $topf_name;
  sysopen(TOP_OUT, $top_file, O_WRONLY | O_CREAT | O_EXCL)
    or die "Can't open top file to create: $!";
  # Open template top file
  open TOP_IN, "<$static_dir/prof_tmpl.py" or die "Can't open template top file: $!";
  # Go through template top file, modify key words and print to new top file
  while( my $line = <TOP_IN> )
  {
     $line =~ s/HB_ALIFILE_HB/$input_ali/g;
     $line =~ s/HB_GAP_PEN_1D_HB/$gap_pen_1D/g;
     $line =~ s/HB_BLOCK1SEQS_HB/$seq_count_1/g;
     $line =~ s/HB_ALI_OUT_HB/$output_ali/g;
     print TOP_OUT $line;
  }   
       
  close TOP_IN;
  close TOP_OUT;
}


# Create top file for fasta->pir change
sub faa2pir_topf
{
  my $job_dir = shift;
  my $output_ali = shift;
  my $static_dir = shift;
  my $input_ali = shift;
  my $input_format = shift;
  my $topf_name = shift;

  # create top file
  my $top_file = $job_dir . '/' . $topf_name;
  sysopen(TOP_OUT, $top_file, O_WRONLY | O_CREAT | O_EXCL)
    or die "Can't open top file to create: $!";
  
  # Open template top file
  open TOP_IN, "<$static_dir/faa2pir_tmpl.py" or die "Can't open template top file: $!";
  # Go through template top file, modify key words and print to new top file
  while( my $line = <TOP_IN> )
  {
     $line =~ s/HB_ALIFILE_HB/$input_ali/g;
     $line =~ s/HB_ALIFORMAT_HB/$input_format/g;
     $line =~ s/HB_ALI_OUT_HB/$output_ali/g;
     print TOP_OUT $line;
  }   
  close TOP_IN;
  close TOP_OUT;
}

sub print_job_submission{
	my ($self, $job, $email) = @_;
        chdir('/');
        $job->submit($email);
        my $job_name = $job->name;
        my $results = $job->results_url;
        my $contact = $self->contact_url;
	my $msg = <<SUBMIT1;
<div id="fullpart"><h1> Job Submitted </h1>
<hr />
<p>
	Your job has been submitted to the server and was assigned job id: $job_name.
</p>
<p>
	Please save the job id for your reference.
</p>
<p>
        Results will be found at <a href="$results">this link</a>.
</p>
SUBMIT1
        if ($email) {
            $msg .= <<EMAIL;
<p>
	You will be sent a notification email when job results are available.
</p>
EMAIL
        }
	$msg .= <<SUBMIT2;
<p>
	If you experience any problems or if you do not receive the results for more than 12 hours, please <a href="$contact">contact us</a>.
</p>
<p>
	Thank you for using our server and good luck in your research!
</p>
</div>
SUBMIT2
	return $msg;
}

1;
