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
	my @declarations;
	while (@TOKENS) {
		my $d = parse_declaration() // die "invalid declaration (missing specifiers)";
		push @declarations, $d;
	}
	return ::Program(\@declarations);
}

sub parse_declaration {
	my @specs = parse_specifiers();
	return undef unless @specs;
	my ($type, $storage_class) = @specs;
	die "missing type" unless defined $type;
	my $name = parse_identifier();
	if (peek()->{values}[0] eq '(') {
		my $params = parse_params_list();
		if (try_expect('Symbol', '{')) {
			return ::FunDeclaration($name, $params, parse_block(), $storage_class);
		} 
		expect('Symbol', ';');
		return ::FunDeclaration($name, $params, undef, $storage_class);
	} else {
		my $init = try_expect('Operator', '=') ? parse_expr(0) : undef;
		expect('Symbol', ';');
		return ::VarDeclaration($name, $init, $storage_class);
	}
}

sub parse_specifiers {
	my (@storage_specs, @type_specs);
	while (my $kw = try_expect('Keyword', 'int', 'static', 'extern')) {
		my $val = $kw->{values}[0];
		if ($val eq 'int') {
			push @type_specs, $val;
		} else {
			push @storage_specs, $val;
		}	
	}
	return () if (!@type_specs && !@storage_specs);
	die "too many type specifiers: @{[@type_specs]}"	if (@type_specs > 1);
	die "too many storage specs: @{[@storage_specs]}"	if (@storage_specs > 1);
	return ($type_specs[0], parse_storage_class($storage_specs[0]));
}

sub parse_storage_class {
	my $storage_spec = shift;
	if (!defined $storage_spec)		{ return undef }
	if ($storage_spec eq 'static')	{ return ::Static() }
	if ($storage_spec eq 'extern')	{ return ::Extern() }
	die "unknown storage specifier: $storage_spec";
}

sub parse_params_list {
	my @list;
	expect('Symbol', '(');
	if (try_expect('Keyword', 'void')) {
		expect('Symbol', ')');
	} else {
		while (1) {
			expect('Keyword', 'int');
			push(@list, ::VarDeclaration(parse_identifier(), undef, undef));	
			last if try_expect('Symbol', ')');
			expect('Symbol', ',');
		} 
	}
	return \@list;
}

sub parse_block {
	my @items;
	while (@TOKENS) {
		last if (try_expect('Symbol', '}'));
		push @items, parse_block_item();
	}
	return ::Block(\@items);
}

sub parse_block_item {
	return parse_declaration() // parse_statement();
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
		expect('Keyword', 'while') && expect('Symbol', '(');
		my $cond = parse_expr(0);
		expect('Symbol', ')') && expect('Symbol', ';');
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
	return undef if (try_expect('Symbol', ';'));
	my $res = parse_declaration();
	if (!defined $res) {
		$res = parse_opt_expr(';');
	} else {
		die "fun declaration in for init" if ($res->{tag} eq 'FunDeclaration');
	}
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
		with (Constant $val) { return ::ConstantExpr($val); }
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
	my ($name) = ::extract_or_die(shift @TOKENS, 'Identifier');
	return $name;
}

sub parse_unop {
	my ($op) = ::extract_or_die(shift(), "Operator");
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
	return $TOKENS[shift() // 0] // die 'peek: no more tokens';
}

sub try_expect {
	my ($tag, @possible_vals) = @_;
	if (peek()->{tag} eq $tag && (!@possible_vals || grep { peek()->{values}[0] eq $_ } @possible_vals)) {
		return shift @TOKENS;
	}	
	return 0;
}

sub expect {
	my ($tag, $val) = @_;
	my $found = shift @TOKENS // die "expected: $tag '$val', but no more tokens";
	if ($found->{tag} eq $tag && (!defined $val || $found->{values}[0] eq $val)) {
		return $found;
	}	
	die "syntax err -> expected: $tag '$val', but found: $found";
}

1;
