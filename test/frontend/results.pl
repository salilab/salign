#!/usr/bin/perl -w

use saliweb::Test;
use Test::More 'no_plan';
use Test::Exception;
use File::Temp qw(tempdir);
use Test::Output qw(stdout_from);

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

# Check job that failed
{
    my $frontend = $t->make_frontend();
    my $job = new saliweb::frontend::CompletedJob($frontend,
                        {name=>'testjob', passwd=>'foo', directory=>'/foo/bar',
                         archive_time=>'2009-01-01 08:45:00'});
    my $tmpdir = tempdir(CLEANUP=>1);
    ok(chdir($tmpdir), "chdir into tempdir");

    ok(open(FH, "> email_info"), "Open email_info");
    print FH "FAIL||\n";
    ok(close(FH), "Close email_info");

    ok(open(FH, "> input.py"), "Open input.py");
    ok(close(FH), "Close input.py");

    my $ret = $frontend->get_results_page($job);
    chdir("/");

    like($ret, '/Your alignment failed.*' .
               'Modeller Input Files.*' .
               'input\.py/ms',
               'get_results_page (failed job)');
}

# Check Chimera launch script
{
    my $frontend = $t->make_frontend();
    my $tmpdir = tempdir(CLEANUP=>1);
    my $job = new saliweb::frontend::CompletedJob($frontend,
                        {name=>'testjob', passwd=>'foo', directory=>$tmpdir,
                         archive_time=>'2009-01-01 08:45:00'});
    ok(chdir($tmpdir), "chdir into tempdir");

    # Should die if no alignment file
    dies_ok { $frontend->download_results_file($job, "showfile.chimerax") };

    ok(open(FH, ">", "str_str_out.ali"), "open alignment file");
    ok(close(FH), "close alignment file");

    my $out = stdout_from { $frontend->download_results_file($job,
                                               "showfile.chimerax") };
    chdir("/");
    like($out, '/^Content\-type: application\/x\-chimerax.*' .
               '<\?xml version="1\.0"\?>.*' .
               '<ChimeraPuppet type="std_webdata">.*' .
               '<web_files>.*' .
               '<file\s+name="alignment\.pir" format="text"  loc=.*' .
               '<commands>.*' .
               '</commands>.*' .
               '</ChimeraPuppet>/ms', "chimera script file");
}

# Check ChimeraX launch script
{
    my $frontend = $t->make_frontend();
    my $tmpdir = tempdir(CLEANUP=>1);
    my $job = new saliweb::frontend::CompletedJob($frontend,
                        {name=>'testjob', passwd=>'foo', directory=>$tmpdir,
                         archive_time=>'2009-01-01 08:45:00'});
    ok(chdir($tmpdir), "chdir into tempdir");

    # Should die if no alignment file
    dies_ok { $frontend->download_results_file($job, "showfile.cxc") };

    ok(open(FH, ">", "str_str_out.ali"), "open alignment file");
    ok(close(FH), "close alignment file");

    my $out = stdout_from { $frontend->download_results_file($job,
                                               "showfile.cxc") };
    chdir("/");
    like($out, '/^Content\-type: text\/plain.*' .
               'close session.*' .
               'open http.*str_str_out\.ali/ms', "chimerax script file");
}
