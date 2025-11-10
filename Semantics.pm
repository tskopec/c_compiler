package Semantics;
use strict;
use warnings;
use feature qw(say state isa signatures);

use ADT::AlgebraicTypes qw(:AST :T :S :I);


our %symbol_table;

sub run {
	%symbol_table = ();
	my $ast = shift;
	resolve_ids($ast);
	check_types($ast);
	label_loops($ast);
}

### IDENTIFIER RESOLUTION ###
sub resolve_ids {
	my $program = shift;
	my $ids_map = {};
	for my $decl ($program->{declarations}->@*) {
		$decl->match({
			AST_FunDeclaration => sub($name, $params, $body, $type, $storage) {
				resolve_fun_declaration_ids($decl, $ids_map, 0);
			}, 
			AST_VarDeclaration => sub($name, $init, $type, $storage) {
				resolve_top_level_var_declaration_ids($decl, $ids_map);
			},
			default => sub() {
				die "unknown declaration: $decl";
			}
		});
	}
}

sub resolve_fun_declaration_ids {
	my ($fun, $ids_map, $in_block_scope) = @_;
	my ($name, $params, $body, $type, $storage) = $fun->values_in_order("AST_FunDeclaration");
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
		my ($items) = $body->values_in_order("AST_Block");
		resolve_block_item_ids($_, $inner_ids_map) for @$items;
	}
}

sub resolve_top_level_var_declaration_ids {
	my ($decl, $ids_map) = @_;
	my ($name, $init, $type, $storage) = $decl->values_in_order('AST_VarDeclaration');
	$ids_map->{$name} = { uniq_name => $name, from_this_scope => 1, has_linkage => 1};
}

sub resolve_local_var_declaration_ids {
	my ($declaration, $ids_map) = @_;
	my ($name, $init, $type, $storage) = $declaration->values_in_order('AST_VarDeclaration');
	if (exists $ids_map->{$name}
		&& $ids_map->{$name}{from_this_scope}
		&& !($ids_map->{$name}{has_linkage} && $storage->is('S_Extern')) {
			die "multiple declarations of $name in this scope, some without linkage";
	}
	if ($storage->is('S_Extern')) {
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
		AST_VarDeclaration => sub($name, $init, $type, $storage) {
			resolve_local_var_declaration_ids($item, $ids_map);
		},
		AST_FunDeclaration => sub($name, $params, $body, $type, $storage) {
			die "local fun definition: $name" if (defined $body);
			resolve_fun_declaration_ids($item, $ids_map, 1);
		},
		default => sub() {
			resolve_statement_ids($item, $ids_map);
		}	
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
		AST_If => sub($cond, $then , $else) {
			resolve_expr_ids($cond, $ids_map);
			resolve_statement_ids($then, $ids_map);
			resolve_statement_ids($else, $ids_map) if defined $else;
		},
		AST_Compound => sub($block) {
			my ($items) = $block->values_in_order('AST_Block');
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
					resolve_local_var_declaration_ids($idecl, $new_idents);
				},
				AST_ForInitExpression => sub($expr) {
					resolve_opt_expr_ids($expr, $new_idents);
				}
			});
			resolve_opt_expr_ids($cond, $new_idents);
			resolve_opt_expr_ids($post, $new_idents);
			resolve_statement_ids($body, $new_idents);
		},
		AST_Break => sub($label) { ; },
		AST_Continue => sub($label) { ; },
		default => sub() { 
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
	$expr->match() ({
		AST_ConstantExpr => sub($val, $type) {;},
		AST_Cast => sub($expr, $type) { 
			resolve_expr_ids($expr, , $ids_map);
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
			resolve_expr_ids($, $ids_map) for ($cond, $then, $else); 
		},
		AST_FunctionCall => sub($name, $args, $type) {
			$expr->set('ident', ($ids_map->{$name}{uniq_name} // die "calling undeclared function $name"));
			resolve_expr_ids($_, $ids_map) for @$args;
		},
		default { die "unknown expression $expr" }
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

# TODO

### TYPE CHECKING ###
sub check_types {
	state $current_fun_ret_type;
	my ($node, $parent_node) = @_;
	if ($node isa Types::Algebraic::ADT) {
		match ($node) {
			with (FunDeclaration $name $params $body $ret_type $storage) {
				$current_fun_ret_type = $ret_type;
				my $f_type = ::FunType([ 
						map { my ($name, $init, $p_type, $storage) = ::extract_or_die($_, 'VarDeclaration'); $p_type } @$params 
					],
					$ret_type);
				my $has_body = defined($body);
				my $already_defined = 0;
				my $global = $storage->{tag} ne 'Static';

				if (exists $symbol_table{$name}) {
					$already_defined = get_symbol_attr($name, 'defined');
					die "incompatible declarations: $name"			unless (types_equal(get_symbol_attr($name, 'type'), $f_type));
					die "fun defined multiple times: $name"			if ($already_defined && $has_body);
					die "static fun declaration after non-static"	if (get_symbol_attr($name, 'global') && !$global);
					$global = get_symbol_attr($name, 'global');
				}
				$symbol_table{$name} = { 
					type => $f_type,
					attrs => ::FunAttrs(
						($already_defined || $has_body),
						0+$global
					)
				};
				if ($has_body) {
					for my $p (@$params) {
						my ($name, $init, $p_type, $storage) = ::extract_or_die($p, 'VarDeclaration');
						$symbol_table{$name} = { type => $p_type, attrs => ::LocalAttrs() };
					}
					check_types($body, $node);
				}
			}
			with (VarDeclaration $name $init $type $storage) {
				my $is_file_scope = $parent_node isa Types::Algebraic::ADT && $parent_node->{tag} eq 'Program';
				if ($is_file_scope) {
					my $init_val;
					if (!defined $init) {
						$init_val = $storage->{tag} eq 'Extern' ? ::NoInitializer() : ::Tentative();
					} else {
						my ($const, $_type) = ::extract_or_die($init, 'ConstantExpr');
						$init_val = const_to_initval($const, $type);
					} 
					my $global = $storage->{tag} ne 'Static';
					
					if (exists $symbol_table{$name}) {
						die "already declared as other type: $name" unless (types_equal(get_symbol_attr($name, 'type'), $type));
						if ($storage->{tag} eq 'Extern') {
							$global = get_symbol_attr($name, 'global');
						} elsif (get_symbol_attr($name, 'global') != $global) {
							die "conflicting linkage, var $name";
						}

						my $prev_init = get_symbol_attr($name, 'init_value');
						if ($prev_init->{tag} eq 'Initial') {
							die "conflicting file scope var definitions: $name " if ($init_val->{tag} eq 'Initial');
							$init_val = $prev_init;
						} elsif ($init_val->{tag} ne 'Initial' && $prev_init->{tag} eq 'Tentative') {
							$init_val = ::Tentative();
						}
					}
					$symbol_table{$name} = { 
						type => $type,
						attrs => ::StaticAttrs($init_val, 0+$global)
					};	
				} else { # local var
					if ($parent_node isa Types::Algebraic::ADT && $parent_node->{tag} eq 'For' && defined($storage)) {
						die "for loop header var $name declaration with storage class";
					}
					if ($storage->{tag} eq 'Extern') {
						die "initalizing local extern variable" if (defined $init);
						if (exists $symbol_table{$name}) {
							die "already declared as other type: $name" unless (types_equal(get_symbol_attr($name, 'type'), $type));
						} else {
							$symbol_table{$name} = {
								type => $type,
								attrs => ::StaticAttrs(::NoInitializer(), 1)
							};
						}
					} elsif ($storage->{tag} eq 'Static') {
						my $init_val;
						if (!defined $init) {
							$init_val = ::Initial(0);
						} else {
							my ($const, $_type) = ::extract_or_die($init, 'ConstantExpr');
							$init_val = const_to_initval($const, $type);
						}
						$symbol_table{$name} = {
							type => $type,
							attrs => ::StaticAttrs($init_val, 0)
						};
					} else {
						$symbol_table{$name} = {
							type => $type,
							attrs => ::LocalAttrs()
						};
						if (defined $init) {
							check_types($init, $node);
						}
					}
				}
			}
			with (FunctionCall $name $args $dummy_type) {
				my ($param_types, $ret_type) = ::extract_or_die(get_symbol_attr($name, 'type'), 'FunType');
				die "wrong number of args: $name" if (@$param_types != @$args);
				while (my ($i, $arg) = each @$args) {
					check_types($arg, $node);
					$args->[$i] = convert_type($arg, $param_types->[$i]);
				}	
				set_type($node, $ret_type);
			}
			with (Var $name $dummy_type) {
				my $type = get_symbol_attr($name, 'type');
				die "is not var: $name" if ($type->{tag} eq 'FunType');
				set_type($node, $type);
			}
			with (ConstantExpr $const $type) {;}
			with (Cast $expr $type) {
				check_types($expr, $node);
				set_type($node, $type);
			}
			with (Unary $op $expr $dummy_type) {
				check_types($expr, $node);
				if ($op->{tag} eq 'Not') { 
					set_type($node, ::Int());
			   	} else { 
					set_type($node, get_type($expr)); 
				}
			}
			with (Binary $op $e1 $e2 $dummy_type) {
				check_types($e1, $node);
				check_types($e2, $node);
				if (::is_one_of($op, 'And', 'Or')) {
					set_type($node, ::Int());
				} else {
					my $common_type = get_common_type(get_type($e1), get_type($e2));
					$node->{values}[1,2] = (convert_type($e1, $common_type), convert_type($e2, $common_type));
					if (::is_one_of($op, 'Add', 'Subtract', 'Multiply', 'Divide', 'Remainder')) {
						set_type($node, $common_type);
					} else {
						set_type($node, ::Int());
					}
				}
			} 
			with (Assignment $lhs $rhs $dummy_type) {
				check_types($lhs, $node);
				check_types($rhs, $node);
				my $left_type = get_type($lhs);
				$node->{values}[1] = convert_type($rhs, $left_type);
				set_type($node, $left_type);
			}
			with (Conditional $cond $then $else $dummy_type) {
				check_types($cond, $node);
				check_types($then, $node);
				check_types($else, $node);
				my $common_type = get_common_type(get_type($then), get_type($else));
				$node->{values}[1,2] = (convert_type($then, $common_type), convert_type($else, $common_type));
				set_type($node, $common_type);
			}	
			with (Return $expr) {
				check_types($expr, $node);
				$node->{values}[0] = convert_type($expr, $current_fun_ret_type);		
			}
			default {
				check_types($_, $node) for $node->{values}->@*;
			}	
		} 
	} elsif (ref($node) eq 'ARRAY') {
		check_types($_, $parent_node) for $node->@*;
	}
}

sub get_symbol_attr {
	my ($symbol, $attr_name) = @_;
	return $symbol_table{$symbol}->{type} if ($attr_name eq 'type');
	my $res;
	match ($symbol_table{$symbol}->{attrs}) {
		with (FunAttrs $defined $global) {
			# TODO zkusit znova rovnou return
			$res = $defined if ($attr_name eq 'defined');
			$res = $global if ($attr_name eq 'global');
		}
		with (StaticAttrs $init_val $global) {
			$res = $init_val if ($attr_name eq 'init_value');
			$res = $global if ($attr_name eq 'global');
		}
		with (LocalAttrs) {;}
		default {
			die "cant get attribute '$attr_name' of $symbol in " . $symbol_table{$symbol}->{attrs};
		}
	}
	return $res; 
}

sub set_type {
	my ($expr, $type) = @_;
	$expr->{values}[-1] = $type;	
}

sub get_type {
	my $expr = shift;
	return $expr->{values}[-1];
}

sub get_common_type {
	my ($t1, $t2) = @_;
	if ($t1->{tag} eq $t2->{tag}) {
		return $t1;
	} else {
		return ::Long();
	}
}

sub convert_type {
	my ($expr, $type) = @_;
	return (get_type($expr) eq $type) ? $expr : ::Cast($expr, $type);
}

sub types_equal {
	my ($t1, $t2) = @_;
	if ($t1->{tag} eq $t2->{tag}) {
		if ($t1->{tag} eq 'FunType') {
			my ($param_types1, $ret_type1) = ::extract($t1, 'FunType');
			my ($param_types2, $ret_type2) = ::extract($t2, 'FunType');
			return 0 if (@$param_types1 != @$param_types2 || $ret_type1 ne $ret_type2);
			return not grep { $param_types1->[$_] ne $param_types2->[$_] } (0..$#$param_types1);
		}	
		return 1;
	} 
	return 0;
}

sub const_to_initval {
	my ($const, $type) = @_;
	my $val = $const->{values}[0];
	return ::Initial(
		($type->{tag} eq 'Int')
			? ::IntInit(fit_integer_into($val, $type))
			: ::LongInit(fit_integer_into($val, $type))
	);
}

sub fit_integer_into {
	state $max_int = 2**31 - 1;
	state $max_uint = 2**32;
	my ($val, $type) = @_;
	if ($type->{tag} eq 'Int') {
		$val -= $max_uint while ($val > $max_int);
	}
	return $val;
}


### LOOP LABELING ###
sub label_loops {
	my ($node, $current_label) = @_;
	if ($node isa Types::Algebraic::ADT) {
		if (::is_one_of($node, 'While', 'DoWhile', 'For')) {
			$current_label = new_loop_label();
			$node->{values}[-1] = $current_label;
		} elsif (::is_one_of($node, 'Break', 'Continue')) {
			$node->{values}[0] = ($current_label // die("'" . lc($node->{tag}) . "' outside loop"));
			return;
		}
		label_loops($_, $current_label) for $node->{values}->@*;
	} elsif (ref($node) eq 'ARRAY') {
		label_loops($_, $current_label) for $node->@*;
	}
}

sub new_loop_label {
	return "_loop_" . $::global_counter++;
}

1;
