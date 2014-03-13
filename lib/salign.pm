package salign;
use base qw(saliweb::frontend);
use strict;

use constant MAX_POST_SIZE => 1073741824; # 1GB maximum upload size
use constant BUFFER_SIZE => 16384; # Buffer size 16Kb

# Never let write directory grow larger than 1 GB
use constant MAX_DIR_SIZE => 1073741824;

# Path for static directory
use constant STATIC_DIR => "/modbase5/home/salign/static";

use salign::Utils;
use salign::CGI_Utils;
use salign::index_page;
use salign::submit_page;
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
<div style="clear:both;"></div>
<div id="address">
<hr />
        <p><b>
        <a target="_blank" href="http://www.ncbi.nlm.nih.gov/pubmed/22618536">
        SALIGN : A webserver for alignment of multiple protein sequences and structures. Bioinformatics 2012; doi: 10.1093/bioinformatics/bts302.<br />Hannes Braberg, Ben Webb, Elina Tjioe, Ursula Pieper, Andrej Sali, Mallur S. Madhusudhan.</a>&nbsp;<a target="_blank" href="http://salilab.org/pdf/Braberg_Bioinformatics_2012.pdf"><img src="http://modbase.compbio.ucsf.edu/salign/pdf.gif" alt="PDF" /></a><br />
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
}

1;
