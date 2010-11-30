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

# Check job that produced no output
{
    my $frontend = $t->make_frontend();
    my $job = new saliweb::frontend::CompletedJob($frontend,
                        {name=>'testjob', passwd=>'foo', directory=>'/foo/bar',
                         archive_time=>'2009-01-01 08:45:00'});
    my $ret = $frontend->get_results_page($job);
    like($ret, '/Results for SALIGN run \'<b>testjob</b>\'\W+<\/p>\W+' .
               '<div class="results">\W+<\/div>/ms',
               'get_results_page (empty)');
}

# Check job that took an input Python script and generated a log file
{
    my $frontend = $t->make_frontend();
    my $job = new saliweb::frontend::CompletedJob($frontend,
                        {name=>'testjob', passwd=>'foo', directory=>'/foo/bar',
                         archive_time=>'2009-01-01 08:45:00'});
    my $tmpdir = tempdir(CLEANUP=>1);
    ok(chdir($tmpdir), "chdir into tempdir");

    ok(open(FH, "> input.py"), "Open input.py");
    ok(close(FH), "Close input.py");

    ok(open(FH, "> output.log"), "Open output.log");
    ok(close(FH), "Close output.log");

    my $ret = $frontend->get_results_page($job);
    chdir("/");

    like($ret, '/<h3>\W+Modeller Input Files\W+<\/h3>\W+' .
               '<p>\W+<a href=.*>input.py<\/a>\W+<\/p>\W+' .
               '<h3>\W+Log Files\W+<\/h3>\W+' .
               '<p>\W+<a href=.*>output.log<\/a>\W+<\/p>\W+/ms',
               'get_results_page (input and output)');
}
