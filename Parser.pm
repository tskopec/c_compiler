package Parser;
use strict;
use warnings;
use feature qw(say state);
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
	return ::Program(\@fns);
}

sub parse_function {
	expect(['Keyword', 'int']);
	my $name = parse_identifier();
	expect(['Symbol', '('], ['Keyword', 'void'], ['Symbol', ')', '{']);
	my $body = parse_statement();
	expect(['Symbol', '}']);
	return ::FunctionDeclaration($name, [$body]);
}

sub parse_statement {
	expect(['Keyword', 'return']);	
	my $ret_val = parse_expr(0);
	expect(['Symbol', ';']);
	return ::Return($ret_val);
}

sub parse_factor {
	my $token = shift @TOKENS;
	match ($token) {
		with (Constant $val) { return ::ConstantExp($val) }
		with (Operator $op) {
			my $op_node = parse_unop($token);
			return ::Unary($op_node, parse_factor());
		}
		with (Symbol $char) {
			if ($char eq '(') {
				my $inner = parse_expr(0);
				expect(["Symbol", ")"]);
				return $inner;
			}
		}
	}
	die "cant parse $token as factor";
}


sub parse_expr {
	my $min_prec = shift;
	my $left = parse_factor();
	while (my ($op) = ::extract(peek(), 'Operator')) {
		last if precedence($op) < $min_prec;
		my $op_node = parse_binop(+shift @TOKENS);
		my $right = parse_expr(precedence($op) + 1);
		$left = ::Binary($op_node, $left, $right);
	}
	return $left;
}

sub parse_identifier {
	my $iden = expect(["Identifier"]);
	return $iden->{values}[0];
}

sub parse_unop {
	my ($op) = ::extract_or_die(shift, "Operator");
	state $map = {
		'-' => ::Negate(),
		'~' => ::Complement(),
		'!' => ::Not(),
	};
	return $map->{$op} // die "unknown unop $op";
}

sub parse_binop {
	my ($op) = ::extract_or_die(shift, "Operator");
	state $map = {
		'+' => ::Add(),
		'-' => ::Subtract(),
		'*' => ::Multiply(),
		'/' => ::Divide(),
		'%' => ::Modulo(),
		'&&' => ::And(),
		'||' => ::Or(),
		'==' => ::Equal(),
		'!=' => ::NotEqual(),
		'<'  => ::LessThan(),
		'<=' => ::LessOrEqual(),
		'>'  => ::GreaterThan(),
		'>=' => ::GreaterOrEqual(),
	};
	return $map->{$op} // die "unknown binop $op";
}

sub precedence {
	my $op = shift;
	return 50 if $op =~ /\*|\/|%/;
	return 45 if $op =~ /\+|-/;
	return 35 if $op =~ /<=|>=|<|>|/;
	return 30 if $op =~ /==|!=/;
	return 10 if $op eq '&&';
	return 5  if $op eq '||';
	die "no precedence defined for $op";
}

sub peek {
	return $TOKENS[0];
}

sub expect {
	my $found;
	for my $expected (@_) {
		my ($exp_tag, @exp_values) = @$expected;
		for (my $i = 0; $i <= @exp_values; $i++) {
			$found = shift @TOKENS;
			if ($found->{tag} ne $exp_tag) {
				die "syntax error: expected exp_tag $exp_tag found " . $found->{tag};
			}
			my $exp_value = shift @exp_values // next;
			if ($found->{values}[0] ne $exp_value) {
				die "syntax error: expected exp_value $exp_value found " . $found->{values}[0];
			}
		}
	}
	return $found;
}

1;
