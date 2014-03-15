package salign::results_page;

use CGI; 
use CGI::Carp qw(fatalsToBrowser);
use lib "/modbase5/home/salign/perl_lib";
use Salign::CGI_Error;
use Salign::Utils;
use File::Find;
use Cwd;
use Fcntl qw( :DEFAULT :flock);
use POSIX qw(strftime);
use DB_File;

sub display_ok_job {
    my ($self, $q, $job) = @_;

    my $msg = $q->b("<br><h1>Results for Salign job id: " . $job->name
                    . "</h1><hr />");
    my @filetypes=("_fit.pdb",".tree",".py",".log",".ali");
    $msg .= "\n<table width=\"90%\" align=\"center\">";
    foreach $filetype (@filetypes) {
        $msg .= show_files($q,$job,$filetype);
    }

    $msg .= "</table>";
    $msg .= $job->get_results_available_time();
    return $msg;
}

sub show_files {

	my $q=shift @_;
	my $job=shift @_;
	my $type=shift @_;
	my %title;
	$title{"_fit.pdb"}="Fitted Coordinate Files";
	$title{'.tree'}="Dendrogram";
	$title{'.py'}="Modeller Input Files";
	$title{'.ali'}="Alignment Files";
	$title{'.log'}="Log Files";
        my $msg = $q->Tr($q->td({-colspan=>"2"},$q->br,$q->b($title{$type})));
        @uploadinfo = glob("\*$type");
	foreach $uploadinfo (@uploadinfo) {
		
		($filename,$date,$size)=&get_fileinfo($uploadinfo);
		$msg .= $q->Tr($q->td($q->a({-href=>$job->get_results_file_url($filename)},$filename)),$q->td($size),$q->td($date));
	}
	#hb 050216
	if ( $type eq '_fit.pdb' && $#uploadinfo > -1 )
	{
            $msg .= $q->Tr($q->td($q->a({-href=>$job->get_results_file_url("showfile.chimerax")},"Launch Chimera")));
        }  
    return $msg;
}

sub get_fileinfo {

		my $uploadinfo=shift @_;

                $filename=$uploadinfo;
		@filenames=split("/",$filename);
		$filename=pop @filenames;
                chomp $filename;
		my ($filesize, $mtime);
		(undef, undef, undef, undef, undef, undef, undef, $filesize,
                 undef, $mtime, undef, undef, undef) = stat($uploadinfo);
		$date = strftime "%b %d %H:%M", localtime($mtime);
                if ($filesize > 500000) {
                        $size=$filesize/1048576;
                        $size=sprintf "%.2f",$size;
                        $size=$size." MB";
                } elsif ($filesize > 500) {
                        $size=$filesize/1024;
                        $size=sprintf "%.2f",$size;
                        $size=$size." KB";
                } else {
                        $size=$filesize;
                        $size=sprintf "%d",$size;
                        $size=$size." B";
                }
		return ($filename,$date,$size);
}

1;
