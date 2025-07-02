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
	expect('Keyword', 'int');
	my $name = parse_identifier();
	expect('Symbol', '(', 'Keyword', 'void', 'Symbol', ')', '{');
	my $body = [];
	while (@TOKENS && peek()->{values}[0] ne '}') {
		push @$body, parse_block_item();
	}
	shift @TOKENS;
	return ::Function($name, $body);
}

sub parse_block_item {
	if (peek() eq ::Keyword('int')) {
		return ::D(parse_declaration());
	} else {
		return ::S(parse_statement());
	}
}

sub parse_declaration {
	expect('Keyword', 'int');
	my $name = parse_identifier();
	my $init;
	if (try_expect('Operator', '=')) {
		$init = parse_expr(0);
	}
	expect('Symbol', ';');
	return ::Declaration($name, $init);
}

sub parse_statement {
	if (try_expect('Keyword', 'return')) {
		my $ret_val = parse_expr(0);
		expect('Symbol', ';');
		return ::Return($ret_val);
	} elsif (try_expect('Symbol', ';')){
		return ::Null();
	} elsif (try_expect('Keyword', 'if')) {
		expect('Symbol', '(');
		my $cond = parse_expr(0);	
		expect('Symbol', ')');
		my $then = parse_statement();
		my $else = parse_statement() if try_expect('Keyword', 'else'); 
		return ::If($cond, $then, $else);
	} else {
		my $expr = parse_expr(0);
		expect('Symbol', ';');
		return ::Expression($expr);
	}
}

sub parse_expr {
	my $min_prec = shift;
	my $left = parse_factor();
	while (my ($op) = ::extract(peek(), 'Operator')) {
		last if precedence($op) < $min_prec;
		if ($op eq '=') {
			shift @TOKENS;
			my $right = parse_expr(precedence($op));
			$left = ::Assignment($left, $right);
		} else {
			my $op_node = parse_binop(shift @TOKENS);
			my $right = parse_expr(precedence($op) + 1);
			$left = ::Binary($op_node, $left, $right);
		}
	}
	return $left;
}

sub parse_factor {
	my $token = shift @TOKENS;
	match ($token) {
		with (Constant $val) { return ::ConstantExp($val) }
		with (Identifier $name) { return ::Var($name) }
		with (Operator $op) {
			my $op_node = parse_unop($token);
			return ::Unary($op_node, parse_factor());
		}
		with (Symbol $char) {
			if ($char eq '(') {
				my $inner = parse_expr(0);
				expect("Symbol", ")");
				return $inner;
			}
		}
	}
	die "cant parse $token as factor";
}

sub parse_identifier {
	my $iden = expect_any("Identifier");
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
	return 1  if $op eq '=';
	die "no precedence defined for $op";
}

sub peek {
	return $TOKENS[0];
}

sub expect {
	my ($found, $expected_tag);
	for my $arg (@_) {
		if ($arg =~ /^[A-Z]/) {
			$expected_tag = $arg;
		} else {
			$found = shift @TOKENS;
			if ($found->{tag} ne $expected_tag || $found->{values}[0] ne $arg) {
				die "syntax err: expected $expected_tag $arg, found $found";
			}
		}	
	}
	return $found;
}

sub expect_any {
	my $expected_tag = shift;
	my $found = shift @TOKENS;
	if ($found->{tag} ne $expected_tag) {
		die "syntax err: expected $expected_tag, found $found";
	}
	return $found;
}

sub try_expect {
	my ($tag, $value) = @_;
	my $found = peek();
	if ($found->{tag} eq $tag && $found->{values}[0] eq $value) {
		shift @TOKENS;
		return 1;
	}
	return 0;
}


1;
