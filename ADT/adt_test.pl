#!/usr/bin/env perl
use strict;
use warnings;
use feature qw(say);

use lib '.';
use Types;

my $u = Unary(Minus(), Constant(7));
say $u;

if (my ($op, $inner) = match($u, 'Unary')) {
	say "match unary: " . $op->{tag} . " " . $inner->{tag};
}
if (match($u, 'Binary')) {
	die "nejakej renonc asi";
}


die "konec";
