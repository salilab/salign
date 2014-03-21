#!/usr/bin/perl -w

use saliweb::Test;
use Test::More 'no_plan';

BEGIN {
    use_ok('salign');
}

my $t = new saliweb::Test('salign');

# Test get_index_page
{
    my $self = $t->make_frontend();
    my $txt = $self->get_index_page();
    like($txt, qr/SALIGN is a general alignment module/ms,
         'get_index_page');
}
