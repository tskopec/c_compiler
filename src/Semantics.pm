package Semantics;
use strict;
use warnings;
use feature qw(say state isa signatures);

use ADT::AlgebraicTypes qw(:AST :A :I :S :T is_ADT);
use TypeUtils qw(/^MAX_/ get_common_type get_common_pointer_type convert_type convert_as_if_by_assignment types_equal
	const_to_initval);

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
		die "static nested fun" if (is_ADT($storage, 'S_Static'));
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
	$ids_map->{$name} = { uniq_name => $name, from_this_scope => 1, has_linkage => 1 };
}

sub resolve_local_var_declaration_ids {
	my ($declaration, $ids_map) = @_;
	my ($name, $init, $type, $storage) = $declaration->values_in_order('AST_VarDeclaration');
	if (exists $ids_map->{$name}
		&& $ids_map->{$name}{from_this_scope}
		&& !($ids_map->{$name}{has_linkage} && is_ADT($storage, 'S_Extern'))) {
		die "multiple declarations of $name in this scope, some without linkage";
	}
	if (is_ADT($storage, 'S_Extern')) {
		$ids_map->{$name} = { uniq_name => $name, from_this_scope => 1, has_linkage => 1 };
	} else {
		$declaration->set('name', unique_var_name($name));
		$ids_map->{$name} = { uniq_name => $declaration->get('name'), from_this_scope => 1, has_linkage => 0 };
		resolve_expr_ids($init, $ids_map) if (defined $init);
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
		"AST_Return, AST_ExprStatement" => sub($e) {
			resolve_expr_ids($e, $ids_map);
		},
		AST_Null => sub() { ; },
		AST_If => sub($cond, $then, $else) {
			resolve_expr_ids($cond, $ids_map);
			resolve_statement_ids($then, $ids_map);
			resolve_statement_ids($else, $ids_map) if (defined $else);
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
		"AST_Break, AST_Continue" => sub($label) { ; },
		default => sub {
			die "unknown statement $statement"
		}
	});
}

sub resolve_opt_expr_ids {
	my ($expr, $ids_map) = @_;
	resolve_expr_ids($expr, $ids_map) if (defined $expr);
}

sub resolve_expr_ids {
	my ($expr, $ids_map) = @_;
	$expr->match({
		AST_ConstantExpr => sub($const, $type) { ; },
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
		AST_Assignment => sub($le, $re, $type) {
			resolve_expr_ids($_, $ids_map) for ($le, $re);
		},
		AST_Conditional => sub($cond, $then, $else, $type) {
			resolve_expr_ids($_, $ids_map) for ($cond, $then, $else);
		},
		AST_FunctionCall => sub($name, $args, $type) {
			$expr->set('ident', ($ids_map->{$name}{uniq_name} // die "calling undeclared function $name"));
			resolve_expr_ids($_, $ids_map) for @$args;
		},
		AST_Dereference => sub($e, $type) {
			resolve_expr_ids($e, $ids_map);
		},
		AST_AddrOf => sub($e, $type) {
			resolve_expr_ids($e, $ids_map);
		},
		default => sub { die "unknown expression $expr" }
	});
}

sub unique_var_name { # TODO inline?
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
			AST_FunDeclaration => sub($name, $params, $body, $fun_type, $storage) {
				$current_fun_ret_type = $fun_type->get('ret_type');
				my $has_body = defined($body);
				my $already_defined = 0;
				my $global = not is_ADT($storage, 'S_Static');

				if (exists $symbol_table{$name}) {
					$already_defined = get_symbol_attr($name, 'defined');
					die "incompatible declarations: $name" if (!types_equal(get_symbol_attr($name, 'type'), $fun_type));
					die "fun defined multiple times: $name" if ($already_defined && $has_body);
					die "static fun declaration after non-static" if (get_symbol_attr($name, 'global') && !$global);
					$global = get_symbol_attr($name, 'global');
				}
				$symbol_table{$name} = {
					type => $fun_type,
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
###### file scope var
				if ($is_file_scope) {
					my $init_val;
					if (is_ADT($init, 'AST_ConstantExpr')) {
						$init_val = const_to_initval($init->get('constant'), $type);
					} elsif (!defined($init)) {
						$init_val = is_ADT($storage, 'S_Extern') ? I_NoInitializer() : I_Tentative();
					} else {
						die "initializer is not a constant: $init";
					}
					my $global = not (is_ADT($storage, 'S_Static'));

					if (exists $symbol_table{$name}) {
						die "already declared as other type: $name" unless (types_equal(get_symbol_attr($name, 'type'), $type));
						if (is_ADT($storage, 'S_Extern')) {
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
###### local var
				} else {
					if ($parent_node isa 'ADT::ADT' && $parent_node->is('AST_ForInitDeclaration') && defined($storage)) {
						die "for loop header var $name declaration with storage class";
					}
					if (is_ADT($storage, 'S_Extern')) {
						die "initalizing local extern variable" if (defined $init);
						if (exists $symbol_table{$name}) {
							die "already declared as other type: $name" unless (types_equal(get_symbol_attr($name, 'type'), $type));
						} else {
							$symbol_table{$name} = {
								type => $type,
								attrs => A_StaticAttrs(I_NoInitializer(), 1)
							};
						}
					} elsif (is_ADT($storage, 'S_Static')) {
						my $init_val;
						if (is_ADT($init, 'AST_ConstantExpr')) {
							$init_val = const_to_initval($init->get('constant'), $type);
						} elsif (!defined $init) {
							$init_val = I_Initial(I_IntInit(0));
						} else {
							die "initializer not constant: $init";
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
				if (defined $init) {
					$node->set('initializer', convert_as_if_by_assignment($init, $type));
				}
			},
			AST_FunctionCall => sub($name, $args, $dummy_type) {
				my ($param_types, $ret_type) = (get_symbol_attr($name, 'type'))->values_in_order('T_FunType');
				die "wrong number of args: $name" if (@$param_types != @$args);
				while (my ($i, $arg) = each @$args) {
					check_types($arg, $node);
					$args->[$i] = convert_as_if_by_assignment($arg, $param_types->[$i]);
				}
				$node->set('type', $ret_type);
			},
			AST_Var => sub($name, $dummy_type) {
				my $type = get_symbol_attr($name, 'type');
				die "is not var: $name" if ($type->is('T_FunType'));
				$node->set('type', $type);
			},
			AST_ConstantExpr => sub($const, $type) { ; },
			AST_Cast => sub($expr, $type) {
				check_types($expr, $node);
				if (($expr->get('type')->is('T_Double') && $type->is('T_Pointer'))
					|| ($expr->get('type')->is('T_Pointer') && $type->is('T_Double'))) {
					die "cant convert $expr to $type";
				}
				$node->set('type', $type);
			},
			AST_Unary => sub($op, $expr, $dummy_type) {
				check_types($expr, $node);
				my $expr_type = $expr->get('type');
				$op->match({
					AST_Complement => sub {
						die "cant complement $expr_type" if ($expr_type->is('T_Double', 'T_Pointer'));
					},
					AST_Negate => sub {
						die "cant negate $expr_type" if ($expr_type->is('T_Pointer'));
					},
					AST_Not => sub {
						$expr_type = T_Int;
					}
				});
				$node->set('type', $expr_type);
			},
			AST_Binary => sub($op, $e1, $e2, $dummy_type) {
				check_types($e1, $node);
				check_types($e2, $node);
				my $is_pointer_op = $e1->get('type')->is('T_Pointer') || $e2->get('type')->is('T_Pointer');
				die "cant $op pointer" if ($is_pointer_op && $op->is('AST_Multiply', 'AST_Divide', 'AST_Remainder'));

				if ($op->is('AST_And', 'AST_Or')) {
					$node->set('type', T_Int());
				} else {
					my $common_type = $is_pointer_op && $op->is('AST_Equal', 'AST_NotEqual')
						? get_common_pointer_type($e1, $e2)
						: get_common_type($e1->get('type'), $e2->get('type'));
					$node->set('expr1', convert_type($e1, $common_type));
					$node->set('expr2', convert_type($e2, $common_type));
					die "cant apply '%' to double" if ($common_type->is('T_Double') && $op->is('AST_Remainder'));
					if ($op->is('AST_Add', 'AST_Subtract', 'AST_Multiply', 'AST_Divide', 'AST_Remainder')) {
						$node->set('type', $common_type);
					} else {
						$node->set('type', T_Int);
					}
				}
			},
			AST_Assignment => sub($lhs, $rhs, $dummy_type) {
				die "$lhs not lvalue" unless is_lval($lhs);
				check_types($lhs, $node);
				check_types($rhs, $node);
				$node->set('rhs', convert_as_if_by_assignment($rhs, $lhs->get('type')));
				$node->set('type', $lhs->get('type'));
			},
			AST_Conditional => sub($cond, $then, $else, $dummy_type) {
				check_types($cond, $node);
				check_types($then, $node);
				check_types($else, $node);
				my $common_type = $then->get('type')->is('T_Pointer') || $else->get('type')->is('T_Pointer')
					? get_common_pointer_type($then, $else)
					: get_common_type($then->get('type'), $else->get('type'));
				$node->set('then', convert_type($then, $common_type));
				$node->set('else', convert_type($else, $common_type));
				$node->set('type', $common_type);
			},
			AST_Return => sub($expr) {
				check_types($expr, $node);
				$node->set('expr', convert_as_if_by_assignment($expr, $current_fun_ret_type));
			},
			AST_Dereference => sub($expr, $dummy_type) {
				check_types($expr, $node);
				$expr->get('type')->match({
					T_Pointer => sub($to_type) {
						$node->set('type', $to_type);
					},
					default => sub { die "cant dereference $expr" }
				});
			},
			AST_AddrOf => sub($expr, $dummy_type) {
				die "$expr not lvalue" unless is_lval($expr);
				check_types($expr, $node);
				$node->set('type', T_Pointer($expr->get('type')));
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
	($symbol_table{$symbol}->{attrs})->match({
		A_FunAttrs => sub($defined, $global) {
			return $defined if ($attr_name eq 'defined');
			return $global if ($attr_name eq 'global');
		},
		A_StaticAttrs => sub($init_val, $global) {
			return $init_val if ($attr_name eq 'init_value');
			return $global if ($attr_name eq 'global');
		},
		A_LocalAttrs => sub() { return undef },
		default => sub {
			die "cant get attribute '$attr_name' of $symbol in " . $symbol_table{$symbol}->{attrs};
		}
	});
}

sub is_lval {
	return shift()->is('AST_Var', 'AST_Dereference');
}

#3# LOOP LABELING ###
sub label_loops {
	my ($node, $current_label) = @_;
	if ($node isa 'ADT::ADT') {
		if ($node->is('AST_While', 'AST_DoWhile', 'AST_For')) {
			$current_label = "_loop_" . $::global_counter++;
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

1;
