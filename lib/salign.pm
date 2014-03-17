package salign;
use base qw(saliweb::frontend);
use strict;

use salign::Utils;
use salign::CGI_Utils;
use salign::index_page;
use salign::submit_page;
use salign::results_page;
use salign::chimera;
use salign::constants;
use Cwd;
use CGI;
use Fcntl qw( :DEFAULT :flock);
use DB_File;

# Limit size of uploaded files
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
<div style="clear:both;"></div>
<div id="address">
<hr />
        <p><b>
        <a target="_blank" href="http://www.ncbi.nlm.nih.gov/pubmed/22618536">
        SALIGN : A webserver for alignment of multiple protein sequences and structures. Bioinformatics 2012; doi: 10.1093/bioinformatics/bts302.<br />Hannes Braberg, Ben Webb, Elina Tjioe, Ursula Pieper, Andrej Sali, Mallur S. Madhusudhan.</a>&nbsp;<a target="_blank" href="http://salilab.org/pdf/Braberg_Bioinformatics_2012.pdf"><img src="$htmlroot/pdf.gif" alt="PDF" /></a><br />
        </b></p>
</div>
FOOTER
}

sub get_index_page {
    my $self = shift;
    my $q = $self->cgi;
    return salign::index_page::main($self, $q);
}

sub get_submit_page {
    my $self = shift;
    my $q = $self->cgi;
    return salign::submit_page::fpmain($self, $q);
}

sub get_results_page {
    my ($self, $job) = @_;
    my $q = $self->cgi;
    open(FH, "email_info") or die "Cannot open: $!";
    my $info = <FH>;
    close(FH) or die "Cannot close: $!";
    my $failmsg;
    if ($info =~ /^OK/) {
        $failmsg = '';
    } else {
        $failmsg = $q->b("Your alignment failed <br /> Details may be found " .
                         "in the log files <br /><br />");
    }
    return salign::results_page::display_job($self, $q, $job, $failmsg);
}

sub download_results_file {
    my ($self, $job, $file) = @_;
    if ($file =~ /showfile\.chimerax/) {
        salign::chimera::showfile($self, $job);
    } else {
        $self->SUPER::download_results_file($job, $file);
    }
}

sub get_job_object {
    my ($self, $job_name) = @_;
    my $job;
    if ($job_name) {
        $job = $self->resume_job($job_name);
    } else {
        $job = $self->make_job("job");
        mkdir $job->directory . "/upload"
          or die "Can't create sub directory " . $job->directory
                 . "/upload: $!\n";
    }
    return $job;
}

sub templatedir {
    my ($self) = @_;
    return $self->txtdir . '/template';
}

1;
