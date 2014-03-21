#!/usr/bin/perl -w

use saliweb::Test;
use Test::More 'no_plan';
use File::Temp qw(tempdir);

BEGIN {
    use_ok('salign::Utils');
}

# Test ascii_chk
{
    my $tmpdir = tempdir(CLEANUP=>1);
    ok(chdir($tmpdir), "chdir into tempdir");

    ok(open(FILE, ">", "f"), "open file");
    print FILE "foo";
    ok(close(FILE), "close file");

    is(ascii_chk('.', 'f'), 1, "ascii file");

    ok(open(FILE, ">", "f"), "open file");
    print FILE "\0";
    ok(close(FILE), "close file");

    is(ascii_chk('.', 'f'), 0, "binary file");

    chdir('/')
}
