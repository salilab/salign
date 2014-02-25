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
    like($ret, '/Results for SALIGN run \'<b>testjob</b>\'\s*<\/p>\s*' .
               '<div class="results">\s*<\/div>/ms',
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

    like($ret, '/<h3>\s*Modeller Input Files\s*<\/h3>\s*' .
               '<p>\s*<a href=.*>input.py<\/a>\s*<\/p>\s*' .
               '<h3>\s*Log Files\s*<\/h3>\s*' .
               '<p>\s*<a href=.*>output.log<\/a>\s*<\/p>\s*/ms',
               'get_results_page (input and output)');
}
