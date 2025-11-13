package Semantics;
use strict;
use warnings;
use feature qw(say state isa signatures);

use ADT::AlgebraicTypes qw(:AST :A :I :S :T);


our %symbol_table;

sub run {
	%symbol_table = ();
	my $ast = shift;
	resolve_ids($ast);
	check_types($ast);
	label_loops($ast);
}

#1# IDENTIFIER RESOLUTION ##########################################
sub resolve_ids {
	my $program = shift;
	my $ids_map = {};
	for my $decl (@{$program->get('declarations')}) {
		$decl->match({
			AST_FunDeclaration => sub($name, $params, $body, $type, $storage) {
				resolve_fun_declaration_ids($name, $params, $body, $type, $storage, $ids_map, 0);
			},
			AST_VarDeclaration => sub($name, $init, $type, $storage) {
				resolve_top_level_var_declaration_ids($name, $init, $type, $storage, $ids_map);
			},
			default => sub {
				die "unknown declaration: $decl";
			}
		});
	}
}

sub resolve_fun_declaration_ids {
	my ($name, $params, $body, $type, $storage,
		$ids_map, $in_block_scope) = @_;
	if ($in_block_scope) {
		die "nested fun definition" if (defined $body);
		die "static nested fun" if ($storage->is('S_Static'));
	}
	if (exists $ids_map->{$name}) {
		my $previous_entry = $ids_map->{$name};
		if ($previous_entry->{from_this_scope} && !$previous_entry->{has_linkage}) {
			die "duplicate function declaration $name";
		}
	}
	$ids_map->{$name} = { uniq_name => $name, from_this_scope => 1, has_linkage => 1 };
	my $inner_ids_map = make_inner_scope_map($ids_map);
	resolve_local_var_declaration_ids($_, $inner_ids_map) for @$params;
	if (defined $body) {
		my $items = $body->get('items');
		resolve_block_item_ids($_, $inner_ids_map) for @$items;
	}
}

sub resolve_top_level_var_declaration_ids {
	my ($name, $init, $type, $storage,
	   	$ids_map) = @_;
	$ids_map->{$name} = { uniq_name => $name, from_this_scope => 1, has_linkage => 1};
}

sub resolve_local_var_declaration_ids {
	my ($declaration, $ids_map) = @_;
	my ($name, $init, $type, $storage) = $declaration->values_in_order('AST_VarDeclaration');
	if (exists $ids_map->{$name}
		&& $ids_map->{$name}{from_this_scope}
		&& !($ids_map->{$name}{has_linkage} && $storage->is('S_Extern'))) {
			die "multiple declarations of $name in this scope, some without linkage";
	}
	if (defined $storage && $storage->is('S_Extern')) {
		$ids_map->{$name} = { uniq_name => $name, from_this_scope => 1, has_linkage => 1 };
	} else {
		$declaration->set('name', unique_var_name($name));
		$ids_map->{$name} = { uniq_name => $declaration->get('name'), from_this_scope => 1, has_linkage => 0 };
		resolve_expr_ids($init, $ids_map) if defined $init;
	}
}

sub resolve_block_item_ids {
	my ($item, $ids_map) = @_;
	$item->match({
		AST_BlockDeclaration => sub($decl) {
			$decl->match({
				AST_VarDeclaration => sub($name, $init, $type, $storage) {
					resolve_local_var_declaration_ids($decl, $ids_map);
				},
				AST_FunDeclaration => sub($name, $params, $body, $type, $storage) {
					die "local fun definition: $name" if (defined $body);
					resolve_fun_declaration_ids($name, $params, $body, $type, $storage, $ids_map, 1);
				},
			});
		},
		AST_BlockStatement => sub($stat) {
			resolve_statement_ids($stat, $ids_map);
		},
	});
}

sub resolve_statement_ids {
	my ($statement, $ids_map) = @_;
	$statement->match({
		AST_Return => sub($e) {
			resolve_expr_ids($e, $ids_map);
		},
		AST_Expression => sub($e) {
			resolve_expr_ids($e, $ids_map);
		},
		AST_Null => sub() { ; },
		AST_If => sub($cond, $then, $else) {
			resolve_expr_ids($cond, $ids_map);
			resolve_statement_ids($then, $ids_map);
			resolve_statement_ids($else, $ids_map) if defined $else;
		},
		AST_Compound => sub($block) {
			my $items = $block->get('items');
			my $new_idents = make_inner_scope_map($ids_map);
			resolve_block_item_ids($_, $new_idents) for @$items;
		},
		AST_While => sub($cond, $body, $label) {
			resolve_expr_ids($cond, $ids_map);
			resolve_statement_ids($body, $ids_map);
		},
		AST_DoWhile => sub($body, $cond, $label) {
			resolve_statement_ids($body, $ids_map);
			resolve_expr_ids($cond, $ids_map);
		},
		AST_For => sub($init, $cond, $post, $body, $label) {
			my $new_idents = make_inner_scope_map($ids_map);
			$init->match({
				AST_ForInitDeclaration => sub($decl) {
					resolve_local_var_declaration_ids($decl, $new_idents);
				},
				AST_ForInitExpression => sub($expr) {
					resolve_opt_expr_ids($expr, $new_idents);
				}
			});
			resolve_opt_expr_ids($cond, $new_idents);
			resolve_opt_expr_ids($post, $new_idents);
			resolve_statement_ids($body, $new_idents);
		},
		AST_Break => sub($label) {;},
		AST_Continue => sub($label) {;},
		default => sub {
			die "unknown statement $statement"
		}
	});
}

sub resolve_opt_expr_ids {
	my ($expr, $ids_map) = @_;
	resolve_expr_ids($expr, $ids_map) if defined $expr;
}

sub resolve_expr_ids {
	my ($expr, $ids_map) = @_;
	$expr->match({
		AST_ConstantExpr => sub($val, $type) {;},
		AST_Cast => sub($expr, $type) {
			resolve_expr_ids($expr, $ids_map);
		},
		AST_Var => sub($name, $type) {
			$expr->set('ident', ($ids_map->{$name}{uniq_name} // die "undeclared variable $name"));
		},
		AST_Unary => sub($op, $e, $type) {
			   resolve_expr_ids($e, $ids_map);
		},
		AST_Binary => sub($op, $e1, $e2, $type) {
			resolve_expr_ids($_, $ids_map) for ($e1, $e2);
		},
		AST_Assignment	=> sub($le, $re, $type) {
			die "not a variable $le" if (!$le->is('AST_Var'));
			resolve_expr_ids($_, $ids_map) for ($le, $re);
		},
		AST_Conditional => sub($cond, $then, $else, $type) {
			resolve_expr_ids($_, $ids_map) for ($cond, $then, $else);
		},
		AST_FunctionCall => sub($name, $args, $type) {
			$expr->set('ident', ($ids_map->{$name}{uniq_name} // die "calling undeclared function $name"));
			resolve_expr_ids($_, $ids_map) for @$args;
		},
		default => sub { die "unknown expression $expr" }
	});
}

sub unique_var_name {
	return shift() . '.' . $::global_counter++;
}

sub make_inner_scope_map {
	my $original_ids = shift;
	my $result = {};
	while (my ($name_in_src, $properties) = each %$original_ids) {
		while (my ($k, $v) = each %$properties) {
			$result->{$name_in_src}{$k} = $v;
		}
		$result->{$name_in_src}{from_this_scope} = 0;
	};
	return $result;
}




#2# TYPE CHECKING ##########################################
sub check_types {
	state $current_fun_ret_type;
	my ($node, $parent_node) = @_;
	if ($node isa 'ADT::ADT') {
		$node->match({
			AST_FunDeclaration => sub($name, $params, $body, $ret_type, $storage) {
				$current_fun_ret_type = $ret_type;
				my $f_type = T_FunType([ map { $_->get('type') } @$params ], $ret_type);
				my $has_body = defined($body);
				my $already_defined = 0;
				my $global = defined $storage && !$storage->is('S_Static');

				if (exists $symbol_table{$name}) {
					$already_defined = get_symbol_attr($name, 'defined');
					die "incompatible declarations: $name"			if (!types_equal(get_symbol_attr($name, 'type'), $f_type));
					die "fun defined multiple times: $name"			if ($already_defined && $has_body);
					die "static fun declaration after non-static"	if (get_symbol_attr($name, 'global') && !$global);
					$global = get_symbol_attr($name, 'global');
				}
				$symbol_table{$name} = {
					type => $f_type,
					attrs => A_FunAttrs(
						($already_defined || $has_body),
						0+$global
					)
				};
				if ($has_body) {
					for my $p (@$params) {
						$symbol_table{$p->get('name')} = { type => $p->get('type'), attrs => A_LocalAttrs() };
					}
					check_types($body, $node);
				}
			},
			AST_VarDeclaration => sub($name, $init, $type, $storage) {
				my $is_file_scope = $parent_node isa 'ADT::ADT' && $parent_node->is('AST_Program');
				if ($is_file_scope) {
					my $init_val;
					if (!defined $init) {
						$init_val = $storage->is('S_Extern') ? I_NoInitializer() : I_Tentative();
					} else {
						$init_val = const_to_initval($init->get('constant'), $init->get('type'));
					}
					my $global = not $storage->is('S_Static');

					if (exists $symbol_table{$name}) {
						die "already declared as other type: $name" unless (types_equal(get_symbol_attr($name, 'type'), $type));
						if ($storage->is('S_Extern')) {
							$global = get_symbol_attr($name, 'global');
						} elsif (get_symbol_attr($name, 'global') != $global) {
							die "conflicting linkage, var $name";
						}

						my $prev_init = get_symbol_attr($name, 'init_value');
						if ($prev_init->is('I_Initial')) {
							die "conflicting file scope var definitions: $name " if ($init_val->is('I_Initial'));
							$init_val = $prev_init;
						} elsif (!$init_val->is('I_Initial') && $prev_init->is('I_Tentative')) {
							$init_val = I_Tentative();
						}
					}
					$symbol_table{$name} = {
						type => $type,
						attrs => A_StaticAttrs($init_val, 0+$global)
					};
				} else { # local var
					if ($parent_node isa 'ADT::ADT' && $parent_node->is('AST_ForInitDeclaration') && defined($storage)) {
						die "for loop header var $name declaration with storage class";
					}
					if (defined $storage && $storage->is('S_Extern')) {
						die "initalizing local extern variable" if (defined $init);
						if (exists $symbol_table{$name}) {
							die "already declared as other type: $name" unless (types_equal(get_symbol_attr($name, 'type'), $type));
						} else {
							$symbol_table{$name} = {
								type => $type,
								attrs => A_StaticAttrs(I_NoInitializer(), 1)
							};
						}
					} elsif (defined $storage && $storage->is('S_Static')) {
						my $init_val;
						if (!defined $init) {
							$init_val = I_Initial(0);
						} else {
							$init_val = const_to_initval($init->get('constant'), $init->get('type'));
						}
						$symbol_table{$name} = {
							type => $type,
							attrs => A_StaticAttrs($init_val, 0)
						};
					} else {
						$symbol_table{$name} = {
							type => $type,
							attrs => A_LocalAttrs()
						};
						if (defined $init) {
							check_types($init, $node);
						}
					}
				}
			},
			AST_FunctionCall => sub($name, $args, $dummy_type) {
				my ($param_types, $ret_type) = (get_symbol_attr($name, 'type'))->values_in_order('T_FunType');
				die "wrong number of args: $name" if (@$param_types != @$args);
				while (my ($i, $arg) = each @$args) {
					check_types($arg, $node);
					$args->[$i] = convert_type($arg, $param_types->[$i]);
				}
				$node->set('type', $ret_type);
			},
			AST_Var => sub($name, $dummy_type) {
				my $type = get_symbol_attr($name, 'type');
				die "is not var: $name" if ($type->is('T_FunType'));
				$node->set('type', $type);
			},
			AST_ConstantExpr => sub($const, $type) {;},
			AST_Cast => sub($expr, $type) {
				check_types($expr, $node);
				$node->set('type', $type);
			},
			AST_Unary => sub($op, $expr, $dummy_type) {
				check_types($expr, $node);
				if ($op->is('AST_Not')) {
					$node->set('type', T_Int());
				   } else {
					$node->set('type', $expr->get('type'));
				}
			},
			AST_Binary => sub($op, $e1, $e2, $dummy_type) {
				check_types($e1, $node);
				check_types($e2, $node);
				if ($op->is('AST_And', 'AST_Or')) {
					$node->set('type', T_Int());
				} else {
					my $common_type = get_common_type($e1->get('type'), $e2->get('type'));
					$node->set('expr1', convert_type($e1, $common_type));
					$node->set('expr2', convert_type($e2, $common_type));
					if ($op->is('AST_Add', 'AST_Subtract', 'AST_Multiply', 'AST_Divide', 'AST_Remainder')) {
						$node->set('type', $common_type);
					} else {
						$node->set('type', T_Int());
					}
				}
			},
			AST_Assignment => sub($lhs, $rhs, $dummy_type) {
				check_types($lhs, $node);
				check_types($rhs, $node);
				$node->set('rhs', convert_type($rhs, $lhs->get('type')));
				$node->set('type', $lhs->get('type'));
			},
			AST_Conditional => sub($cond, $then, $else, $dummy_type) {
				check_types($cond, $node);
				check_types($then, $node);
				check_types($else, $node);
				my $common_type = get_common_type($then->get('type'), $else->get('type'));
				$node->set('then', convert_type($then, $common_type));
				$node->set('else', convert_type($else, $common_type));
				$node->set('type', $common_type);
			},
			AST_Return => sub($expr) {
				check_types($expr, $node);
				$node->set('expr', convert_type($expr, $current_fun_ret_type));
			},
			default => sub {
				check_types($_, $node) for $node->values_in_order();
			}
		});
	} elsif (ref($node) eq 'ARRAY') {
		check_types($_, $parent_node) for $node->@*;
	}
}

sub get_symbol_attr {
	my ($symbol, $attr_name) = @_;
	return $symbol_table{$symbol}->{type} if ($attr_name eq 'type');
	my $res;
	($symbol_table{$symbol}->{attrs})->match({
		A_FunAttrs => sub($defined, $global) {
			# TODO zkusit znova rovnou return
			$res = $defined if ($attr_name eq 'defined');
			$res = $global if ($attr_name eq 'global');
		},
		A_StaticAttrs => sub($init_val, $global) {
			$res = $init_val if ($attr_name eq 'init_value');
			$res = $global if ($attr_name eq 'global');
		},
		A_LocalAttrs => sub() {;},
		default => sub {
			die "cant get attribute '$attr_name' of $symbol in " . $symbol_table{$symbol}->{attrs};
		}
	});
	return $res;
}

sub get_common_type {
	my ($t1, $t2) = @_;
	if ($t1->same_type_as($t2)) {
		return $t1;
	} else {
		return T_Long();
	}
}

sub convert_type {
	my ($expr, $type) = @_;
	return $type->same_type_as($expr->get('type')) ? $expr : AST_Cast($expr, $type);
}

sub types_equal {
	my ($t1, $t2) = @_;
	if ($t1->same_type_as($t2)) {
		if ($t1->is('T_FunType')) {
			my ($param_types1, $ret_type1) = $t1->values_in_order('T_FunType');
			my ($param_types2, $ret_type2) = $t2->values_in_order('T_FunType');
			return 0 if (@$param_types1 != @$param_types2 || $ret_type1 ne $ret_type2);
			return not grep { not $param_types1->[$_]->same_type_as($param_types2->[$_]) } (0..$#$param_types1);
		}
		return 1;
	}
	return 0;
}

sub const_to_initval {
	my ($const, $type) = @_;
	return I_Initial($type->is('T_Int')
			? I_IntInit(fit_integer_into($const->get('val'), $type))
			: I_LongInit(fit_integer_into($const->get('val'), $type))
	);
}

sub fit_integer_into {
	state $max_int = 2**31 - 1;
	state $max_uint = 2**32;
	my ($val, $type) = @_;
	if ($type->is('T_Int')) {
		$val -= $max_uint while ($val > $max_int);
	}
	return $val;
}




#3# LOOP LABELING ###
sub label_loops {
	my ($node, $current_label) = @_;
	if ($node isa 'ADT::ADT') {
		if ($node->is('AST_While', 'AST_DoWhile', 'AST_For')) {
			$current_label = new_loop_label();
			$node->set('label', $current_label);
		} elsif ($node->is('AST_Break', 'AST_Continue')) {
			$node->set('label', $current_label // die("'" . $node->{':tag'} . "' outside loop"));
			return;
		}
		label_loops($_, $current_label) for $node->values_in_order();
	} elsif (ref($node) eq 'ARRAY') {
		label_loops($_, $current_label) for $node->@*;
	}
}

sub new_loop_label {
	return "_loop_" . $::global_counter++;
}

1;
