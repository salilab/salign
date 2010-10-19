package salign;
use base qw(saliweb::frontend);
use strict;

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
    my $greeting = <<GREETING;
<p>SALIGN is a general alignment module of the modeling program
<a href="http://salilab.org/modeller/">MODELLER</a>.</p>

<p>The alignments are computed using dynamic programming, making use of
several features of the protein sequences and structures.</p>
GREETING
  return $greeting;
}

sub get_submit_page {
    # TODO
}

sub get_results_page {
    # TODO
}

1;
