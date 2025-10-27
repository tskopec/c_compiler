package Types;
use strict;
use warnings;
use feature qw(say);

use ADTSupport;

sub import {
	shift;
	ADTSupport->import(@_);
}

BEGIN {
	declare("Operator", [
		"Plus", "Minus",
	]);
	declare("Expression", [
		Constant =>	[ value => "Int" ],
		Unary => [ op => "Operator", inner => "Expression" ],
		Binary => [ op => "Operator", e1 => "Expression", e2 => "Expression" ],
	]);
}




1;
