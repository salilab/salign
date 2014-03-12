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

sub get_job_object {
  my ($self, $job_name) = @_;
  my $job;
  if ($job_name) {
    $job = $self->resume_job($job_name);
  } else {
    $job = $self->make_job("job");
    mkdir $job->directory . "/upload"
      or die "Can't create sub directory " . $job->directory . "/upload: $!\n";
  }
  return $job;
}

1;
