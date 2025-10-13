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
		push(@declarations, parse_declaration() // die "not a declaration");
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
			return ::FunDeclaration($name, $params, parse_block(), $type, $storage_class);
		} 
		expect('Symbol', ';');
		return ::FunDeclaration($name, $params, undef, $type, $storage_class);
	} else {
		my $init = try_expect('Operator', '=') ? parse_expr(0) : undef;
		expect('Symbol', ';');
		return ::VarDeclaration($name, $init, $type, $storage_class);
	}
}

sub parse_specifiers {
	my (@storage_specs, @type_specs);
	while (1) {
		if (my $kw = try_expect('Keyword', 'int', 'long')) {
			push @type_specs, $kw->{values}[0];
		} elsif (my $kw = try_expect('Keyword', 'static', 'extern')) {
			push @storage_specs, $kw->{values}[0];
		} else { last }
	}
	die "too many storage specs: @{[@storage_specs]}" if (@storage_specs > 1);
	return () if (!@type_specs && !@storage_specs);
	return (parse_type(@type_specs), parse_storage_class(@storage_specs));
}

sub parse_type {
	my $specs = join(" ", @_);
	if ($specs eq 'int') {
		return ::Int();
	} elsif ($specs =~ /^(long|int long|long int)$/) {
		return ::Long();
	} else {
		die "invalid type specifier '$specs'";
	}
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
			my ($type, $storage) = parse_specifiers();
			die "invalid specifiers for fun param: $type $storage" if (!defined $type || defined $storage);
			push(@list, ::VarDeclaration(parse_identifier(), undef, $type, undef));	
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
	my $res = parse_declaration() // parse_opt_expr(';');
	die "fun declaration in for init" if ($res->{tag} eq 'FunDeclaration');
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
			$left = ::Assignment($left, $right, "dummy_type");
		} elsif ($op eq '?') {
			shift @TOKENS;
			my $then = parse_expr(0);
			expect('Operator', ':');
			my $else = parse_expr(precedence($op));
			$left = ::Conditional($left, $then, $else, "dummy_type");
		} else {
			my $op_node = parse_binop(shift @TOKENS);
			my $right = parse_expr(precedence($op) + 1);
			$left = ::Binary($op_node, $left, $right, "dummy_type");
		}
	}
	return $left;
}

sub parse_factor {
	my $token = shift @TOKENS;
	match ($token) {
		with (IntConstant $val)  { return parse_constant('int', $val); }
		with (LongConstant $val) { return parse_constant('long', $val); }
		with (Identifier $name) { 
			if (try_expect('Symbol', '(')) {
				return ::FunctionCall($name, [], "dummy_type") if (try_expect('Symbol', ')'));
				my @args;
				while (1) {
					push(@args, parse_expr(0));
					last if (try_expect('Symbol', ')'));
					expect('Symbol', ',');
				}
				return ::FunctionCall($name, \@args, "dummy_type");
			} else {
				return ::Var($name);
			}
	   	}
		with (Operator $op) {
			my $op_node = parse_unop($token);
			return ::Unary($op_node, parse_factor(), "dummy_type");
		}
		with (Symbol $char) {
			if ($char eq '(') {
				my ($type, $storage) = parse_specifiers();
				die "storage specifier in cast" if (defined $storage);
				if (defined $type) {
					expect("Symbol", ")");
					my $expr = parse_expr(100);
					return ::Cast($expr, $type);
				} else {
					my $inner = parse_expr(0);
					expect("Symbol", ")");
					return $inner;
				}
			}
		}
	}
	die "cant parse $token as factor";
}

sub parse_constant {
	state $max_long = 2**63 - 1;
	state $max_int = 2**31 - 1;
	my ($type, $val) = @_;
	if ($val > $max_long) {
		die "constant too large for long $val";
	} elsif ($type eq 'int' && $val < $max_int) {
		return ::ConstantExpr(::ConstInt($val), ::Int());
	} else {
		return ::ConstantExpr(::ConstLong($val), ::Long());
	}
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
