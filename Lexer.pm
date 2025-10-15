package Lexer;
use strict;
use warnings;
use feature qw(say);



my $sym_re = qr/^([;}{)(,]).*/;
my $op_re =	qr/^(!=|==|<=|>=|<|>|=|!|\|\||&&|--|-|\+|\*|\/|%|~|\?|:).*/;
my $kw_re =	qr/^(int|long|void|return|if|else|do|while|for|break|continue|static|extern)\b.*/;
my $long_const_re = qr/^(([0-9]+)[lL])\b.*/;
my $const_re = qr/^([0-9]+)\b.*/;
my $iden_re = qr/^([a-zA-Z_]\w*)\b.*/;



sub tokenize {

	my $src = shift;
	my @tokens;

	while ($src) {
		$src =~ s/^\s+//;
		last unless $src;
		if ($src =~ $sym_re) {
			push(@tokens, ::Symbol($1));
		}
		elsif ($src =~ $op_re) {
			push(@tokens, ::Operator($1));
		}
		elsif ($src =~ $kw_re) {
			push(@tokens, ::Keyword($1));
		}	
		elsif ($src =~ $long_const_re) {
			push(@tokens, ::LongConstant($2));
		}
		elsif ($src =~ $const_re) {
			push(@tokens, ::IntConstant($1));
		}
		elsif ($src =~ $iden_re) {
			push(@tokens, ::Identifier($1));
		} else {
			die "neznam token -> $src";
		}
		$src = substr($src, length $1);
	} 
	
	return @tokens;
}

1;
