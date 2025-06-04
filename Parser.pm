package Parser;
use strict;
use warnings;
use feature qw(say);
use Types::Algebraic;

my @TOKENS;

sub parse {
	@TOKENS = @_;
	return parse_program();
}

sub parse_program {
	my @fns;
	while (@TOKENS) {
		push @fns, parse_function();
	}
	return ::Program([@fns]);
}

sub parse_function {
	expect('Keyword', 'int');
	my $name = parse_identifier();
	expect('Symbol', '(');
	expect('Keyword', 'void');
	expect('Symbol', ')', '{');
	my $body = parse_statement();
	expect('Symbol', '}');
	return ::FunctionDeclaration($name, [$body]);
}

sub parse_statement {
	expect('Keyword', 'return');	
	my $ret_val = parse_expr();
	expect('Symbol', ';');
	return ::Return($ret_val);
}

sub parse_expr {
	my $token = shift @TOKENS;
	match ($token) {
		with (Constant $val) { return ::ConstantExp($val) }
		with (UnOp $op) { 
			my $op_node = $op eq '-' ? ::Negate()
						: $op eq '~' ? ::Complement()
					   	: die "unknown op $op";
		   	return ::Unary($op_node, parse_expr())
	   	}
		with (Symbol $char) {
			if ($char eq '(') {
				my $inner = parse_expr();
				expect("Symbol", ")");
				return $inner;
			} 
			die "unexpected symbol $char";
		}
		default { die "unexpected token: $token" }
	}
}

sub parse_identifier {
	my $iden = expect("Identifier");
	return $iden->{values}[0];
}

sub expect {
	my ($type, @values) = @_;
	while(1) {
		my $found = shift @TOKENS;
		if ($found->{tag} ne $type) {
			die "syntax error: expected type $type found " . $found->{tag};
		} 
		my $expected_val = shift @values // return $found;
		if ($expected_val ne $found->{values}[0]) {
			die "syntax error: expected value $expected_val found " . $found->{values}[0];
		}
		return $found unless @values;
	}
}

sub peek {
	return $TOKENS[0];
}

1;
