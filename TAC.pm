package TAC;
use strict;
use warnings;
use feature qw(say state);
use Types::Algebraic;
use SemanticAnalysis;


sub emit_TAC {
	my ($node, $instructions) = @_;
	match ($node) {
		with (Program $declarations) {
			my (@tac_funs, @tac_vars);
			for my $d (@$declarations) {
				next if ($d->{tag} ne 'FunDeclaration');
				my $tac_fun = emit_TAC($d);
				push(@tac_funs, $tac_fun) if (defined $tac_fun);
			}
			@tac_vars = covert_symbols_to_TAC();
			return ::TAC_Program([@tac_vars, @tac_funs]);
		}
		with (FunDeclaration $name $params $body $type $storage) {
			if (defined $body) {
				my ($items) = ::extract_or_die($body, 'Block');
				my $instructions = [];
				for my $item (@$items) {
					emit_TAC($item, $instructions);
				}
				push @$instructions, ::TAC_Return(::TAC_Constant(0));
				return ::TAC_Function($name, 
									  SemanticAnalysis::get_symbol_attr($name, 'global'),
									  [ map { $_->{values}[0] } @$params ],
									  $instructions);
			} else {
				return undef;
			}	
		}
		with (VarDeclaration $name $init $type $storage) { 
			if (defined $init) {
				emit_TAC(::Assignment(::Var($name), $init), $instructions);
			}
	   	}
		with (Return $exp) {
			push(@$instructions, ::TAC_Return(emit_TAC($exp, $instructions)));
		}
		with (Null) {;}
		with (If $cond $then $else) {
			my ($else_label) = labels('else') if defined $else;
			my ($end_label) = labels('end');
			my $cond_res = emit_TAC($cond, $instructions);
			push @$instructions, ::TAC_JumpIfZero($cond_res, defined $else ? $else_label : $end_label);
			emit_TAC($then, $instructions);
			push @$instructions, ::TAC_Jump($end_label);
			if (defined $else) {
				push @$instructions, ::TAC_Label($else_label);
				emit_TAC($else, $instructions);
			}
			push @$instructions, ::TAC_Label($end_label);
		}
		with (Compound $block) {
			my ($items) = ::extract_or_die($block, 'Block');
			emit_TAC($_, $instructions) for @$items;	
		}
		with (DoWhile $body $cond $label) {
			my ($start_label) = labels('start');
			push @$instructions, ::TAC_Label($start_label);
			emit_TAC($body, $instructions);
			push @$instructions, ::TAC_Label("_continue$label");
			my $cond_res = emit_TAC($cond, $instructions);
			push(@$instructions, (::TAC_JumpIfNotZero($cond_res, $start_label),
								  ::TAC_Label("_break$label")));
		}
		with (While $cond $body $label) {
			push @$instructions, ::TAC_Label("_continue$label");
			my $cond_res = emit_TAC($cond, $instructions);
			push @$instructions, ::TAC_JumpIfZero($cond_res, "_break$label");
			emit_TAC($body, $instructions);
			push(@$instructions, (::TAC_Jump("_continue$label"),
								  ::TAC_Label("_break$label")));
		}
		with (For $init $cond $post $body $label) {
			my ($start_label) = labels('start');
			emit_TAC($init, $instructions) if defined $init;
			push @$instructions, ::TAC_Label($start_label);
			if (defined $cond) {
				my $cond_res = emit_TAC($cond, $instructions);
				push @$instructions, ::TAC_JumpIfZero($cond_res, "_break$label");
			}
			emit_TAC($body, $instructions);
			push @$instructions, ::TAC_Label("_continue$label");
			emit_TAC($post, $instructions) if defined $post;
			push(@$instructions, (::TAC_Jump($start_label),
								  ::TAC_Label("_break$label")));
		}
		with (Break $label) {
			push @$instructions, ::TAC_Jump("_break$label");
		}
		with (Continue $label) {
			push @$instructions, ::TAC_Jump("_continue$label");
		}
		with (Expression $expr) { emit_TAC($expr, $instructions); }
		with (ConstantExpr $val) {
			return ::TAC_Constant($val);
		}
		with (Var $ident $type) {
			return ::TAC_Variable($ident);
		}
		with (Unary $op $exp $type) {
			my $unop = convert_unop($op);
			my $src = emit_TAC($exp, $instructions);
			my $dst = ::TAC_Variable(temp_name());
			push @$instructions, ::TAC_Unary($unop, $src, $dst);	
			return $dst;
		}
		with (Binary $op $exp1 $exp2 $type) {
			my $dst = ::TAC_Variable(temp_name());
			if ($op->{tag} eq 'And') {
				my ($false_label, $end_label) = labels(qw(false end));
				my $src1 = emit_TAC($exp1, $instructions);
				push @$instructions, ::TAC_JumpIfZero($src1, $false_label);
				my $src2 = emit_TAC($exp2, $instructions);
				push(@$instructions, ::TAC_JumpIfZero($src2, $false_label),
									 ::TAC_Copy(::TAC_Constant(1), $dst),
									 ::TAC_Jump($end_label),
									 ::TAC_Label($false_label),
									 ::TAC_Copy(::TAC_Constant(0), $dst),
									 ::TAC_Label($end_label));
			} elsif ($op->{tag} eq 'Or') {
				my ($true_label, $end_label) = labels(qw(true end));
				my $src1 = emit_TAC($exp1, $instructions);
				push @$instructions, ::TAC_JumpIfNotZero($src1, $true_label);
				my $src2 = emit_TAC($exp2,  $instructions);
				push(@$instructions, ::TAC_JumpIfNotZero($src2, $true_label),
									 ::TAC_Copy(::TAC_Constant(0), $dst),
									 ::TAC_Jump($end_label),
									 ::TAC_Label($true_label),
									 ::TAC_Copy(::TAC_Constant(1), $dst),
									 ::TAC_Label($end_label));
			} else {
				my $binop = convert_binop($op);
				my $src1 = emit_TAC($exp1, $instructions);
				my $src2 = emit_TAC($exp2, $instructions);
				push @$instructions, ::TAC_Binary($binop, $src1, $src2, $dst);
			}
			return $dst;
		}
		with (Assignment $var $expr $type) {
			my $tac_var = emit_TAC($var, $instructions);
			my $value = emit_TAC($expr, $instructions);
			push @$instructions, ::TAC_Copy($value, $tac_var);
			return $tac_var;
		}
		with (Conditional $cond $then $else $type) {
			my $res = ::TAC_Variable(temp_name());
			my ($e2_label, $end_label) = labels(qw(e2 end));
			my $cond_res = emit_TAC($cond, $instructions);
			push @$instructions, ::TAC_JumpIfZero($cond_res, $e2_label);
			my $e1_res = emit_TAC($then, $instructions);
			push @$instructions, (::TAC_Copy($e1_res, $res),
								  ::TAC_Jump($end_label),
			 					  ::TAC_Label($e2_label));
			my $e2_res = emit_TAC($else, $instructions);
			push @$instructions, (::TAC_Copy($e2_res, $res),
								  ::TAC_Label($end_label)); 
			return $res;
		}
		with (FunctionCall $name $args $type) {
			my $dst = ::TAC_Variable(temp_name());
			my $arg_vals = [ map { emit_TAC($_, $instructions) } @$args ];
			push(@$instructions, (::TAC_FunCall($name, $arg_vals, $dst)));
			return $dst;
		}
		default {
			die "unknown AST node: $node";
		}
	}
}

sub convert_unop {
	my $op = shift;
	state $map = {
		Complement => ::TAC_Complement(),
		Negate => ::TAC_Negate(),
		Not => ::TAC_Not(),
	};
	return $map->{$op->{tag}} // die "unknown unop $op";
}

sub convert_binop {
	my $op = shift;
	state $map = {
		 Add => ::TAC_Add(),
		 Subtract => ::TAC_Subtract(),
		 Multiply => ::TAC_Multiply(),
		 Divide => ::TAC_Divide(),
		 Modulo => ::TAC_Modulo(),
		 And => ::TAC_And(),
		 Or => ::TAC_Or(),
		 Equal => ::TAC_Equal(),
		 NotEqual => ::TAC_NotEqual(),
		 LessThan => ::TAC_LessThan(),
		 LessOrEqual => ::TAC_LessOrEqual(),
		 GreaterThan => ::TAC_GreaterThan(),
		 GreaterOrEqual => ::TAC_GreaterOrEqual(),
	};
	return $map->{$op->{tag}} //  die "unknown bin op $op";
}

sub temp_name {
	return "tmp." . $::global_counter++;
}

sub labels {
	my @res = map { "_${_}_" . $::global_counter } @_;
	$::global_counter++;
	return @res;
}

sub covert_symbols_to_TAC {
	my @tac_vars;
	while (my ($name, $entry) = each %$SemanticAnalysis::symbol_table) {
		if ($entry->{attrs}{tag} eq 'StaticAttrs') {
			my ($init, $global) = ::extract_or_die($entry->{attrs}, 'StaticAttrs');
			match (SemanticAnalysis::get_symbol_attr($name, 'init_value')) {
				with (Initial $i) {
					push(@tac_vars, ::TAC_StaticVariable($name, $global, $i));
				}
				with (Tentative) {
					push(@tac_vars, ::TAC_StaticVariable($name, $global, 0));
				}
				with (NoInitializer) {;}
			}
		}
	}
	return @tac_vars;
}


1;

