#!/usr/bin/perl -w

use saliweb::Test;
use Test::Exception;
use Test::More 'no_plan';
use File::Temp qw(tempdir);

BEGIN {
    use_ok('salign::CGI_Utils');
}

# Test filen_fix
{
    my $f = filen_fix(undef, "/foo/bar/ aA0 b-_.z ");
    is($f, "aA0_b-_.z", "filen_fix valid file");

    throws_ok { filen_fix(undef, "/foo/bar/ a#^A0 b-_.z ") }
              saliweb::frontend::InputValidationError,
              "filen_fix invalid file";
}

# Test filen_fix_jr
{
    my $f = filen_fix_jr(undef, " aA0 b-_.z ");
    is($f, "_aA0_b-_.z_", "filen_fix_jr valid file");

    throws_ok { filen_fix_jr(undef, "a#^A0 b-_.z") }
              saliweb::frontend::InputValidationError,
              "filen_fix_jr invalid file";
}
