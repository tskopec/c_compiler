package Lexer;
use strict;
use warnings;
use feature qw(say);

sub tokenize {
	my $src = shift;
	my @tokens;

	while ($src) {
		$src =~ s/^\s+//;
		last unless $src;
		if ($src =~ /^([;}{)(]).*/) {
			push(@tokens, ::Symbol($1));
		}
		elsif ($src =~ /^(!=|==|<=|>=|<|>|!|\|\||&&|--|-|\+|\*|\/|%|~).*/) {
			push(@tokens, ::Operator($1));
		}
		elsif ($src =~ /^(int|void|return)\b.*/) {
			push(@tokens, ::Keyword($1));
		}	
		elsif ($src =~ /^([0-9]+)\b.*/) {
			push(@tokens, ::Constant($1));
		}
		elsif ($src =~ /^([a-zA-Z_]\w*)\b.*/) {
			push(@tokens, ::Identifier($1));
		} else {
			die "neznam token -> $src";
		}
		$src = substr($src, length $1);
	} 
	
	return @tokens;
}

1;
