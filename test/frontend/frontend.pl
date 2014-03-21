#!/usr/bin/perl -w

use saliweb::Test;
use Test::More 'no_plan';

BEGIN {
    use_ok('salign');
}

my $t = new saliweb::Test('salign');

# Test get_navigation_links
{
    my $self = $t->make_frontend();
    my $links = $self->get_navigation_links();
    isa_ok($links, 'ARRAY', 'navigation links');
    like($links->[0], qr#<a href="http://modbase/top/">SALIGN Home</a>#,
         'Index link');
    like($links->[1],
         qr#<a href="http://modbase/top/queue.cgi">SALIGN Current queue</a>#,
         'Queue link');
}

# Test get_project_menu
{
    my $self = $t->make_frontend();
    my $p = $self->get_project_menu();
    like($p, '/Developers:.*Hannes Braberg.*Version/ms', "get_project_menu");
}

# Test get_footer
{
    my $self = $t->make_frontend();
    my $p = $self->get_footer();
    like($p, '/SALIGN : A webserver/ms', "get_footer");
}

# Test templatedir
{
    my $self = $t->make_frontend();
    $self->{config}->{directories}->{install} = "/foo/bar";
    my $t = $self->templatedir;
    is($t, '/foo/bar/txt/template', "templatedir");
}
