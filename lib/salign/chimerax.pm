package salign::chimerax;

use strict;

sub showfile {
    my ($self, $job) = @_;
    my @pdbfiles = glob("*fit.pdb");
    my @alignfiles = glob("*str_out.ali");
    if (scalar(@alignfiles) != 1) {
        die "Unexpected number of alignment files";
    }
    my $alignfile = $alignfiles[0];

    print "Content-type: application/x-chimerax\n\n";
    print "close session\n";
    foreach my $pdbfile (@pdbfiles) {
        print "open " . $job->get_results_file_url($pdbfile) . "\n";
    }
    print "open " . $job->get_results_file_url($alignfile) . "\n";
    # Assume models are numbered sequentially
    foreach my $i (1 .. $#pdbfiles + 1) {
        print "sequence associate #$i model$i\@\n";
    }
}

1;
