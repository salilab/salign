#!/usr/bin/perl -w

use saliweb::Test;
use Test::More 'no_plan';
use File::Temp;
use Cwd;

BEGIN {
    use_ok('salign');
}

my $t = new saliweb::Test('salign');

# Check job submission

# Submit str-str job
{
    my $self = $t->make_frontend();
    my $cgi = $self->cgi;
    $self->{config}->{directories}->{install} = getcwd();

    my $tmpdir = File::Temp::tempdir(CLEANUP=>1);
    ok(chdir($tmpdir), "chdir into tempdir");

    ok(mkdir("incoming"), "mkdir incoming");

    my $job = $self->get_job_object();

    $cgi->param('job_name', $job->name);
    $cgi->param('tool', 'str_str');
    $cgi->param('align_type', 'tree');
    $cgi->param('weight_mtx', '');
    $cgi->param('libsegm_1abc', '1:A:2:B');
    $cgi->param('1D_open_stst', '5');
    $cgi->param('1D_elong_stst', '1');
    $cgi->param('3D_open', '50');
    $cgi->param('3D_elong', '10');
    $cgi->param('fw_1', '0.1');
    $cgi->param('fw_2', '0.2');
    $cgi->param('fw_3', '0.3');
    $cgi->param('fw_4', '0.4');
    $cgi->param('fw_5', '0.5');
    $cgi->param('fw_6', '0.6');
    $cgi->param('RMS_cutoff', '1');
    $cgi->param('gap-gap_score', '2');
    $cgi->param('gap-res_score', '3');
    $cgi->param('fit', 'FIT');
    $cgi->param('improve', 'IMPROVE');
    $cgi->param('write_whole', 'WHOLE');

    my $s = $self->get_submit_page();

    chdir('/')
}
