package salign::chimera;

use strict;

sub showfile {
    my ($self, $job) = @_;
    my @pdbfiles = glob("*fit.pdb");
    my @alignfiles = glob("*out.ali");
    if (scalar(@alignfiles) != 1) {
        die "Unexpected number of alignment files";
    }
    my $alignfile = $alignfiles[0];

    print "Content-type: application/x-chimerax\n\n";
    print "<?xml version=\"1.0\"?>\n";
    print "<ChimeraPuppet type=\"std_webdata\">\n";
    print " \n";
    print "<web_files>\n";
    print "         <file  name=\"alignment.pir\" format=\"text\" ".
          " loc=\"" . $job->get_results_file_url($alignfile) . "\" />\n";

    foreach my $pdbfile (@pdbfiles) {
        print "         <file  name=\"$pdbfile\" format=\"text\" ".
	      " loc=\"" . $job->get_results_file_url($pdbfile) . "\" />\n";
    }
    print "</web_files>\n";
    print <<END;
<commands>
        <py_cmd>chimera.processNewMolecules(chimera.openModels.list(modelTypes=[chimera.Molecule]))</py_cmd>
        <py_cmd>import MultAlignViewer</py_cmd>
        <py_cmd>mols = chimera.openModels.list()</py_cmd>
        <py_cmd>
m=chimera.extension.manager
for i in m.instances:
    if isinstance(i, MultAlignViewer.MAViewer.MAViewer):
        mav = i
        </py_cmd>
        <py_cmd>
for m in mols:
    if not m in mav.associations.keys():
        mav.associate([m])
mav.match(mols[0], mols[1:], iterate=True)</py_cmd>
</commands>
END

    print "</ChimeraPuppet>\n";
}

1;
