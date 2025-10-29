#!/usr/bin/env perl
use strict;
use warnings;
use feature qw(say);

use lib '.';
use Types;


my $i = AST_Unary(Not(), AST_ConstantExpression(AST_ConstInt(5), Int()), Int());
if (my ($op, $e, $t) = $i->match('AST_Unary')) {
	say $op;
	say $e;
	say $t;
}

die "konec";
