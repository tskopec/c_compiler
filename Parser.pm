package Parser;
use strict;
use warnings;
use feature qw(say state signatures);

use Types;

my @TOKENS;

sub parse {
	@TOKENS = @_;
	return parse_program();
}

sub parse_program {
	my @declarations;
	while (@TOKENS) {
		push(@declarations, parse_declaration());
	}
	return AST_Program(\@declarations);
}

sub parse_declaration {
	my @specs = parse_specifiers();
	return undef unless @specs;
	my ($type, $storage_class) = @specs;
	die "missing type" unless defined $type;

	my $name = parse_identifier();
	if (try_expect('Lex_Symbol', '(')) {
		my $params = parse_params_list();
		if (try_expect('Lex_Symbol', '{')) {
			return AST_FunDeclaration($name, $params, parse_block(), $type, $storage_class);
		} 
		expect('Lex_Symbol', ';');
		return AST_FunDeclaration($name, $params, undef, $type, $storage_class);
	} else {
		my $init = try_expect('Lex_Operator', '=') ? parse_expr(0) : undef;
		expect('Lex_Symbol', ';');
		return AST_VarDeclaration($name, $init, $type, $storage_class);
	}
}

sub parse_specifiers {
	my (@storage_specs, @type_specs);
	while (1) {
		my $kw;
		if ($kw = try_expect('Lex_Keyword', 'int', 'long')) {
			push @type_specs, $kw->{word};
		} elsif ($kw = try_expect('Lex_Keyword', 'static', 'extern')) {
			push @storage_specs, $kw->{word};
		} else { last }
	}
	die "too many storage specs: @{[@storage_specs]}" if (@storage_specs > 1);
	return () if (!@type_specs && !@storage_specs);
	return (parse_type(@type_specs), parse_storage_class(@storage_specs));
}

sub parse_type {
	my $specs = join(" ", @_);
	if ($specs eq 'int') {
		return Int();
	} elsif ($specs =~ /^(long|int long|long int)$/) {
		return Long();
	} else {
		die "invalid type specifier '$specs'";
	}
}

sub parse_storage_class {
	my $storage_spec = shift;
	if (!defined $storage_spec)		{ return undef }
	if ($storage_spec eq 'static')	{ return Static() }
	if ($storage_spec eq 'extern')	{ return Extern() }
	die "unknown storage specifier: $storage_spec";
}

sub parse_params_list {
	my @list;
	if (try_expect('Lex_Keyword', 'void')) {
		expect('Lex_Symbol', ')');
	} else {
		while (1) {
			my ($type, $storage) = parse_specifiers();
			die "invalid specifiers for fun param: $type $storage" if (!defined $type || defined $storage);
			push(@list, AST_VarDeclaration(parse_identifier(), undef, $type, undef));	
			last if try_expect('Lex_Symbol', ')');
			expect('Lex_Symbol', ',');
		} 
	}
	return \@list;
}

sub parse_block {
	my @items;
	while (@TOKENS) {
		last if (try_expect('Lex_Symbol', '}'));
		push @items, parse_block_item();
	}
	return AST_Block(\@items);
}

sub parse_block_item {
	my $decl = parse_declaration();
	return AST_BlockDeclaration($decl) if (defined $decl);
	my $stat = parse_statement();
	return AST_BlockStatement($stat) if (defined $stat);
	die "cant parse block item";
}

sub parse_statement {
	if (try_expect('Lex_Keyword', 'return')) {
		my $ret_val = parse_expr(0);
		expect('Lex_Symbol', ';');
		return AST_Return($ret_val);
	} elsif (try_expect('Lex_Symbol', '{')) {
		return AST_Compound(parse_block());
	} elsif (try_expect('Lex_Symbol', ';')){
		return AST_Null();
	} elsif (try_expect('Lex_Keyword', 'if')) {
		expect('Lex_Symbol', '(');
		my $cond = parse_expr(0);	
		expect('Lex_Symbol', ')');
		my $then = parse_statement();
		my $else = parse_statement() if try_expect('Lex_Keyword', 'else'); 
		return AST_If($cond, $then, $else);
	} elsif (try_expect('Lex_Keyword', 'break')) {
		expect('Lex_Symbol', ';');
		return AST_Break('dummy');
	} elsif (try_expect('Lex_Keyword', 'continue')) {
		expect('Lex_Symbol', ';');
		return AST_Continue('dummy');
	} elsif (try_expect('Lex_Keyword', 'while')) {
		expect('Lex_Symbol', '(');
		my $cond = parse_expr(0);
		expect('Lex_Symbol', ')');
		my $body = parse_statement();
		return AST_While($cond, $body, 'dummy');
	} elsif (try_expect('Lex_Keyword', 'do')) {
		my $body = parse_statement();
		expect('Lex_Keyword', 'while') && expect('Lex_Symbol', '(');
		my $cond = parse_expr(0);
		expect('Lex_Symbol', ')') && expect('Lex_Symbol', ';');
		return AST_DoWhile($body, $cond, 'dummy');
	} elsif (try_expect('Lex_Keyword', 'for')) {
		expect('Lex_Symbol', '(');
		my $init = parse_for_init();
		my $cond = parse_opt_expr(';');
		my $post = parse_opt_expr(')');
		my $body = parse_statement();
		return AST_For($init, $cond, $post, $body, 'dummy');
	} else {
		my $expr = parse_expr(0);
		expect('Lex_Symbol', ';');
		return AST_Expression($expr);
	}
}

sub parse_for_init {
	return undef if (try_expect('AST_Symbol', ';'));
	my $res = parse_declaration() // parse_opt_expr(';');
	die "fun declaration in for init" if ($res->is('AST_FunDeclaration'));
	return $res;
}

sub parse_opt_expr {
	my $end_symbol = shift;
	unless (try_expect('Lex_Symbol', $end_symbol)) {
		my $expr = parse_expr(0);
		expect('Lex_Symbol', $end_symbol);
		return $expr;
	}
	return undef;
}

sub parse_expr {
	my $min_prec = shift;
	my $left = parse_factor();
	while ((peek())->is('Lex_Operator')) {
		my $op = (peek())->{op};
		last if $op eq ':';
		last if precedence($op) < $min_prec;
		if ($op eq '=') {
			shift @TOKENS;
			my $right = parse_expr(precedence($op));
			$left = AST_Assignment($left, $right, DummyType());
		} elsif ($op eq '?') {
			shift @TOKENS;
			my $then = parse_expr(0);
			expect('Lex_Operator', ':');
			my $else = parse_expr(precedence($op));
			$left = AST_Conditional($left, $then, $else, DummyType());
		} else {
			my $op_token = shift @TOKENS;
			my $op_node = parse_binop($op_token->{op});
			my $right = parse_expr(precedence($op) + 1);
			$left = AST_Binary($op_node, $left, $right, DummyType());
		}
	}
	return $left;
}

sub parse_factor {
	my $token = shift @TOKENS;
	my $result = $token->match({
		Lex_IntConstant => sub($val) {
			return parse_constant('int', $val);
		},
		Lex_LongConstant => sub($val) {
			return parse_constant('long', $val);
		},
		Lex_Identifier => sub($name) {
			if (try_expect('Lex_Symbol', '(')) {
				return AST_FunctionCall($name, [], DummyType()) if (try_expect('Lex_Symbol', ')'));
				my @args;
				while (1) {
					push(@args, parse_expr(0));
					last if (try_expect('Lex_Symbol', ')'));
					expect('Lex_Symbol', ',');
				}
				return AST_FunctionCall($name, \@args, DummyType());
			} else {
				return AST_Var($name, DummyType());
			}
		},
		Lex_Operator => sub($op) {
			my $op_node = parse_unop($op);
			return AST_Unary($op_node, parse_factor(), DummyType());
		},
		Lex_Symbol => sub($char) {
			if ($char eq '(') {
				my ($type, $storage) = parse_specifiers();
				die "storage specifier in cast" if (defined $storage);
				if (defined $type) {
					expect("Symbol", ")");
					my $expr = parse_expr(100);
					return AST_Cast($expr, $type);
				} else {
					my $inner = parse_expr(0);
					expect("Symbol", ")");
					return $inner;
				}
			}
		},
		default => sub {
			die "cant parse $token as factor";
		}
	});
	return $result;
}

sub parse_constant {
	state $max_long = 2**63 - 1;
	state $max_int = 2**31 - 1;
	my ($type, $val) = @_;
	if ($val > $max_long) {
		die "constant too large for long $val";
	} elsif ($type eq 'int' && $val < $max_int) {
		return AST_ConstantExpr(AST_ConstInt($val), Int());
	} else {
		return AST_ConstantExpr(AST_ConstLong($val), Long());
	}
}

sub parse_identifier {
	my $token = shift @TOKENS;
	return $token->is('Lex_Identifier') ? $token->{name} : die  "$token not identifier";
}

sub parse_unop {
	my $op = shift;
	state $map = {
		'-' => AST_Negate(),
		'~' => AST_Complement(),
		'!' => AST_Not(),
	};
	return $map->{$op} // die "unknown unop $op"; 
}

sub parse_binop {
	my $op = shift;
	state $map = {
		'+' => AST_Add(),
		'-' => AST_Subtract(),
		'*' => AST_Multiply(),
		'/' => AST_Divide(),
		'%' => AST_Modulo(),
		'&&' => AST_And(),
		'||' => AST_Or(),
		'==' => AST_Equal(),
		'!=' => AST_NotEqual(),
		'<'  => AST_LessThan(),
		'<=' => AST_LessOrEqual(),
		'>'  => AST_GreaterThan(),
		'>=' => AST_GreaterOrEqual(),
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
	my $next = peek();
	if ($next->is($tag)) {
		my $val = ($next->values_in_order())[0]; 
		return shift @TOKENS if (!@possible_vals || grep { $val eq $_ } @possible_vals);
	}
	return 0;
}

sub expect {
	my ($tag, $val) = @_;
	return try_expect($tag, $val) || die("syntax err -> expected: $tag '$val', but found: " . peek());
}

1;
