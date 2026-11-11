package Lexer;
use strict;
use warnings;
use feature qw(say);

use ADT::AlgebraicTypes qw(:LEX);
use Utils qw(unescape_str);

my $sym_re = qr/^([ {} () [\] , ; ])/x;
my $op_re = qr/^(!=|==|<=|>=|<|>|=|!|\|\||&&|->|--|-|\+|\*|\/|%|~|\?|:|&|\.(?!\d))/;
my $kw_re = qr/^(int|long|double|signed|unsigned|void|return|if|else|do|while|for|break|continue|static|extern|char|sizeof|struct)\b/;
my $long_const_re = qr/^((\d+)[lL])[^\w.]/;
my $ulong_const_re = qr/^((\d+)(lu|ul))[^\w.]/i;
my $int_const_re = qr/^(\d+)[^\w.]/;
my $uint_const_re = qr/^((\d+)u)[^\w.]/i;
my $fp_const_re = qr/^(
	(\d*\.\d+|\d+\.?)e[+-]?\d+
	|\d*\.\d+
	|\d+\.
)[^\w.]/xi;
my $char_const_re = qr/^('
	(
		[^'\n\\]
		|\\['"?\\abfnrtv]
	)
')/x;
my $string_literal_re = qr/^("
	(
		([^"\n\\]
		|\\['"\\?abfnrtv])*
	)
")/x;
my $iden_re = qr/^([a-zA-Z_]\w*)\b/;

sub tokenize {
	my $src = shift;
	my @tokens;

	while ($src) {
		$src =~ s/^\s+//;
		last unless $src;
		if ($src =~ $sym_re) {
			push(@tokens, LEX_Symbol($1));
		}
		elsif ($src =~ $op_re) {
			push(@tokens, LEX_Operator($1));
		}
		elsif ($src =~ $kw_re) {
			push(@tokens, LEX_Keyword($1));
		}
		elsif ($src =~ $long_const_re) {
			push(@tokens, LEX_LongConstant($2));
		}
		elsif ($src =~ $ulong_const_re) {
			push(@tokens, LEX_ULongConstant($2));
		}
		elsif ($src =~ $int_const_re) {
			push(@tokens, LEX_IntConstant($1));
		}
		elsif ($src =~ $uint_const_re) {
			push(@tokens, LEX_UIntConstant($2));
		}
		elsif ($src =~ $fp_const_re) {
			push(@tokens, LEX_FPConstant($1));
		}
		elsif ($src =~ $string_literal_re) {
			push(@tokens, LEX_StringLiteral(unescape_str($2)));
		}
		elsif ($src =~ $char_const_re) {
			push(@tokens, LEX_CharConstant(unescape_str($2)));
		}
		elsif ($src =~ $iden_re) {
			push(@tokens, LEX_Identifier($1));
		}
		else {
			die "neznam token -> $src";
		}

		$src = substr($src, length $1);
	}

	return @tokens;
}

1;
