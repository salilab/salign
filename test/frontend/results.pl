#!/usr/bin/perl -w

use saliweb::Test;
use Test::More 'no_plan';
use Test::Exception;
use File::Temp qw(tempdir);

BEGIN {
    use_ok('salign');
    use_ok('saliweb::frontend');
}

my $t = new saliweb::Test('salign');

# Check results page

# Check job that took an input Python script and generated a log file
{
    my $frontend = $t->make_frontend();
    my $job = new saliweb::frontend::CompletedJob($frontend,
                        {name=>'testjob', passwd=>'foo', directory=>'/foo/bar',
                         archive_time=>'2009-01-01 08:45:00'});
    my $tmpdir = tempdir(CLEANUP=>1);
    ok(chdir($tmpdir), "chdir into tempdir");

    ok(open(FH, "> email_info"), "Open email_info");
    print FH "OK||\n";
    ok(close(FH), "Close email_info");

    ok(open(FH, "> test_fit.pdb"), "Open test_fit.pdb");
    ok(close(FH), "Close test_fit.pdb");

    ok(open(FH, "> input.py"), "Open input.py");
    ok(close(FH), "Close input.py");

    ok(open(FH, "> output.log"), "Open output.log");
    ok(close(FH), "Close output.log");

    my $ret = $frontend->get_results_page($job);
    chdir("/");

    like($ret, '/Fitted Coordinate Files.*' .
               'test_fit\.pdb.*' .
               'Modeller Input Files.*' .
               'input\.py.*' .
               'Log Files.*' .
               'output\.log.*/ms',
               'get_results_page (input and output)');
}
