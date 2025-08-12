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
	my $params = parse_params_list();
	if (try_expect('Symbol', '{')) {
		return ::FunDeclaration($name, $params, parse_block());
	} else {
		expect('Symbol', ';');
		return ::FunDeclaration($name, $params, undef);
	}
}


sub parse_params_list {
	my @list;
	expect('Symbol', '(');
	if (try_expect('Keyword', 'void')) {
		push(@list, ['void']);
		expect('Symbol', ')');
	} else {
		while (1) {
			push(@list, [(expect('Keyword', 'int'))->{values}[0], parse_identifier()]);	
			last if try_expect('Symbol', ')');
			expect('Symbol', ',');
		} 
	}
	return \@list;
}

sub parse_block {
	my @items;
	while (@TOKENS && peek()->{values}[0] ne '}') {
		push @items, parse_block_item();
	}
	expect('Symbol', '}');
	return ::Block(\@items);
}

sub parse_block_item {
	return try_parse_declaration() // parse_statement();
}

sub try_parse_declaration {
	my $res;
	if (peek() eq ::Keyword('int')) {
		if (peek(2) eq ::Symbol('(')) {
			$res = parse_function();
		} else {
			expect('Keyword', 'int');
			$res = ::VarDeclaration(parse_identifier(), try_expect('Operator', '=') ? parse_expr(0) : undef);
			expect('Symbol', ';');
		}
	}	
	return $res;
}

sub parse_statement {
	if (try_expect('Keyword', 'return')) {
		my $ret_val = parse_expr(0);
		expect('Symbol', ';');
		return ::Return($ret_val);
	} elsif (try_expect('Symbol', '{')) {
		return ::Compound(parse_block());
	} elsif (try_expect('Symbol', ';')){
		return ::Null();
	} elsif (try_expect('Keyword', 'if')) {
		expect('Symbol', '(');
		my $cond = parse_expr(0);	
		expect('Symbol', ')');
		my $then = parse_statement();
		my $else = parse_statement() if try_expect('Keyword', 'else'); 
		return ::If($cond, $then, $else);
	} elsif (try_expect('Keyword', 'break')) {
		expect('Symbol', ';');
		return ::Break('dummy');
	} elsif (try_expect('Keyword', 'continue')) {
		expect('Symbol', ';');
		return ::Continue('dummy');
	} elsif (try_expect('Keyword', 'while')) {
		expect('Symbol', '(');
		my $cond = parse_expr(0);
		expect('Symbol', ')');
		my $body = parse_statement();
		return ::While($cond, $body, 'dummy');
	} elsif (try_expect('Keyword', 'do')) {
		my $body = parse_statement();
		expect('Keyword', 'while', 'Symbol', '(');
		my $cond = parse_expr(0);
		expect('Symbol', ')', ';');
		return ::DoWhile($body, $cond, 'dummy');
	} elsif (try_expect('Keyword', 'for')) {
		expect('Symbol', '(');
		my $init = parse_for_init();
		my $cond = parse_opt_expr(';');
		my $post = parse_opt_expr(')');
		my $body = parse_statement();
		return ::For($init, $cond, $post, $body, 'dummy');
	} else {
		my $expr = parse_expr(0);
		expect('Symbol', ';');
		return ::Expression($expr);
	}
}

sub parse_for_init {
	my $res;
	if (try_expect('Keyword', 'int')) {
		$res = ::VarDeclaration(parse_identifier(), try_expect('Operator', '=') ? parse_expr(0) : undef);
	} elsif (try_expect('Symbol', ';')) {
		return undef;
	} else {
		$res = parse_expr(0);
	}
	expect('Symbol', ';');
	return $res;
}

sub parse_opt_expr {
	my $end_symbol = shift;
	unless (try_expect('Symbol', $end_symbol)) {
		my $expr = parse_expr(0);
		expect('Symbol', $end_symbol);
		return $expr;
	}
	return undef;
}

sub parse_expr {
	my $min_prec = shift;
	my $left = parse_factor();
	while (my ($op) = ::extract(peek(), 'Operator')) {
		last if $op eq ':';
		last if precedence($op) < $min_prec;
		if ($op eq '=') {
			shift @TOKENS;
			my $right = parse_expr(precedence($op));
			$left = ::Assignment($left, $right);
		} elsif ($op eq '?') {
			shift @TOKENS;
			my $then = parse_expr(0);
			expect('Operator', ':');
			my $else = parse_expr(precedence($op));
			$left = ::Conditional($left, $then, $else);
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
		with (Constant $val) { return ::ConstantExp($val); }
		with (Identifier $name) { 
			if (try_expect('Symbol', '(')) {
				return ::FunctionCall($name, []) if (try_expect('Symbol', ')'));
				my @args;
				while (1) {
					push(@args, parse_expr(0));
					last if (try_expect('Symbol', ')'));
					expect('Symbol', ',');
				}
				return ::FunctionCall($name, \@args);
			} else {
				return ::Var($name);
			}
	   	}
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
	my $iden = expect("Identifier");
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
	return 35 if $op =~ /<=|>=|<|>/;
	return 30 if $op =~ /==|!=/;
	return 10 if $op eq '&&';
	return 5  if $op eq '||';
	return 3  if $op eq '?';
	return 1  if $op eq '=';
	die "no precedence defined for $op";
}

sub peek {
	return $TOKENS[shift() // 0];
}

sub expect {
	my ($found, $expected_tag, $expected_value);
	state $next_arg_is_tag = sub {
		return $_[0] =~ /^[A-Z]/;
	}; 
	die "args: [tag, [values]?], ..." unless $next_arg_is_tag->(@_); 
	while (@_) {
		if ($next_arg_is_tag->(@_)) {
			$expected_tag = shift @_;
			undef $expected_value;
		}
		if (!$next_arg_is_tag->(@_)) {
			$expected_value = shift @_;
		}
		$found = shift @TOKENS // die "no tokens";
		if ($found->{tag} ne $expected_tag || (defined $expected_value && $found->{values}[0] ne $expected_value)) {
			die "syntax err -> expected: $expected_tag '$expected_value', but found: $found";
		}
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
