package SemanticAnalysis;

use strict;
use warnings;
use feature qw(say state isa);
use Types::Algebraic;

our $symbol_table;

sub run {
	$symbol_table = {};
	my $ast = shift;
	resolve_ids($ast);
	check_types($ast);
	label_loops($ast);
}

### IDENTIFIER RESOLUTION ###
sub resolve_ids {
	my ($declarations) = ::extract_or_die(shift(), 'Program'); 
	my $ids_map = {};
	for my $decl (@$declarations) {
		match ($decl) {
			with (FunDeclaration $name $params $body $type $storage) {
				resolve_fun_declaration_ids($decl, $ids_map, 0);
			}
			with (VarDeclaration $name $init $type $storage) {
				resolve_top_level_var_declaration_ids($decl, $ids_map);
			}
			default { die "unknown declaration: $decl" }
		}
	}
}

sub resolve_fun_declaration_ids {
	my ($fun, $ids_map, $in_block_scope) = @_;
	my ($name, $params, $body, $type, $storage) = ::extract_or_die($fun, 'FunDeclaration');
	if ($in_block_scope) {
		die "nested fun definition" if (defined $body);
		die "static nested fun" if ($storage->{tag} eq 'Static');
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
		my ($items) = ::extract($body, 'Block');
		resolve_block_item_ids($_, $inner_ids_map) for @$items;
	}
}

sub resolve_top_level_var_declaration_ids {
	my ($decl, $ids_map) = @_;
	my ($name, $init, $type, $storage) = ::extract_or_die($decl, 'VarDeclaration');
	$ids_map->{$name} = { uniq_name => $name, from_this_scope => 1, has_linkage => 1};
}

sub resolve_local_var_declaration_ids {
	my ($declaration, $ids_map) = @_;
	my ($name, $init, $type, $storage) = ::extract_or_die($declaration, 'VarDeclaration');
	if (exists $ids_map->{$name}
		&& $ids_map->{$name}{from_this_scope}
		&& !($ids_map->{$name}{has_linkage} && $storage->{tag} eq 'Extern')) {
			die "multiple declarations of $name in this scope, some without linkage";
	}
	if ($storage->{tag} eq 'Extern') {
		$ids_map->{$name} = { uniq_name => $name, from_this_scope => 1, has_linkage => 1 };
	} else {
		$declaration->{values}[0] = unique_var_name($name);
		$ids_map->{$name} = { uniq_name => $declaration->{values}[0], from_this_scope => 1, has_linkage => 0 };
		resolve_expr_ids($init, $ids_map) if defined $init;
	}
}

sub resolve_block_item_ids {
	my ($item, $ids_map) = @_;
	match ($item) {
		with (VarDeclaration $name $init $type $storage) {
			resolve_local_var_declaration_ids($item, $ids_map);
		}
		with (FunDeclaration $name $params $body $type $storage) {
			die "local fun definition: $name" if defined $body;
			resolve_fun_declaration_ids($item, $ids_map, 1);
		}
		default {
			resolve_statement_ids($item, $ids_map);
		}
	}
}

sub resolve_statement_ids {
	my ($statement, $ids_map) = @_;
	match ($statement) {
		with (Return $e) { resolve_expr_ids($e, $ids_map); }
		with (Expression $e) { resolve_expr_ids($e, $ids_map); }
		with (Null) {;}
		with (If $cond $then $else) {
			resolve_expr_ids($cond, $ids_map);
			resolve_statement_ids($then, $ids_map);
			resolve_statement_ids($else, $ids_map) if defined $else;
		}
		with (Compound $block) {
			my ($items) = ::extract_or_die($block, 'Block');
			my $new_idents = make_inner_scope_map($ids_map);
			resolve_block_item_ids($_, $new_idents) for @$items; 
		}
		with (While $cond $body $label) {
			resolve_expr_ids($cond, $ids_map);
			resolve_statement_ids($body, $ids_map);
		} 
		with (DoWhile $body $cond $label) {
			resolve_statement_ids($body, $ids_map);
			resolve_expr_ids($cond, $ids_map);
		}
		with (For $init $cond $post $body $label) {
			my $new_idents = make_inner_scope_map($ids_map);
			if (defined $init && $init->{tag} eq 'VarDeclaration') {
				resolve_local_var_declaration_ids($init, $new_idents);
			} else {
				resolve_opt_expr_ids($init, $new_idents);
			}
			resolve_opt_expr_ids($cond, $new_idents);
			resolve_opt_expr_ids($post, $new_idents);
			resolve_statement_ids($body, $new_idents);
		}
		with (Break $label) {;}
		with (Continue $label) {;}
		default { die "unknown statement $statement" }
	}	   
}

sub resolve_opt_expr_ids {
	my ($expr, $ids_map) = @_;
	resolve_expr_ids($expr, $ids_map) if defined $expr;
}

sub resolve_expr_ids {
	my ($expr, $ids_map) = @_;
	match ($expr) {
		with (ConstantExpr $val) {;}
		with (Cast $expr $type) { resolve_expr_ids($expr, $ids_map); }
		with (Var $name $type) { $expr->{values}[0] = ($ids_map->{$name}{uniq_name} // die "undeclared variable $name"); }
		with (Unary $op $e $type) { resolve_expr_ids($e, $ids_map); }
		with (Binary $op $e1 $e2 $type) { resolve_expr_ids($_, $ids_map) for ($e1, $e2); }
		with (Assignment $le $re $type) { 
			die "not a variable $le" if ($le->{tag} ne 'Var');
		   	resolve_expr_ids($_, $ids_map) for ($le, $re);
	   	}
		with (Conditional $cond $then $else $type) { resolve_expr_ids($_, $ids_map) for ($cond, $then, $else); }
		with (FunctionCall $name $args $type) {
			$expr->{values}[0] = ($ids_map->{$name}{uniq_name} // die "calling undeclared function $name");
			resolve_expr_ids($_, $ids_map) for @$args;
		}
		default { die "unknown expression $expr" }
	}
}

sub unique_var_name {
	return +shift . '.' . $::global_counter++;
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



### TYPE CHECKING ###
sub check_types {
	state $current_fun_ret_type;
	my ($node, $parent_node) = @_;
	if ($node isa Types::Algebraic::ADT) {
		match ($node) {
			with (FunDeclaration $name $params $body $ret_type $storage) {
				$current_fun_ret_type = $ret_type;
				my $f_type = ::FunType([ map { my ($name, $init, $p_type, $storage) = ::extract_or_die($_, 'VarDeclaration'); $p_type } @$params ], $ret_type);
				my $has_body = defined($body);
				my $already_defined = 0;
				my $global = $storage->{tag} ne 'Static';

				if (exists $symbol_table->{$name}) {
					$already_defined = get_symbol_attr($name, 'defined');
					die "incompatible fun declarations: $name" if (get_symbol_attr($name, 'type') ne $f_type);
					die "fun defined multiple times: $name" if ($already_defined && $has_body);
					die "static fun declaration after non-static" if (get_symbol_attr($name, 'global') && !$global);
					$global = get_symbol_attr($name, 'global');
				}
				$symbol_table->{$name} = { 
					type => $f_type,
					attrs => ::FunAttrs(
						($already_defined || $has_body),
						0+$global
					)
				};
				if ($has_body) {
					for my $p (@$params) {
						my ($name, $init, $p_type, $storage) = ::extract_or_die($p, 'VarDeclaration');
						$symbol_table->{$name} = { type => $p_type, attrs => ::LocalAttrs() };
					}
					check_types($body, $node, $ret_type);
				}
			}
			with (VarDeclaration $name $init $type $storage) {
				my $is_file_scope = ($parent_node isa Types::Algebraic::ADT) && ($parent_node->{tag} eq 'Program');
				if ($is_file_scope) {
					my $init_val;
					if (!defined $init) {
						$init_val = $storage->{tag} eq 'Extern' ? ::NoInitializer() : ::Tentative();
					} elsif (my $const = ::extract($init, 'ConstantExpr')) {
						$init_val = const_to_initval($const, $type);
					} else {
						die "initializer must be constant";
					}
					my $global = $storage->{tag} ne 'Static';
					
					if (exists $symbol_table->{$name}) {
						die "already declared as other type" if (get_symbol_attr($name, 'type') ne $type);
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
					$symbol_table->{$name} = { 
						type => $type,
						attrs => ::StaticAttrs($init_val, 0+$global)
					};	
				} else { # local var
					if ($parent_node isa Types::Algebraic::ADT && $parent_node->{tag} eq 'For' && defined($storage)) {
						die "for loop header var $name declaration with storage class";
					}
					if ($storage->{tag} eq 'Extern') {
						die "initalizing local extern variable" if (defined $init);
						if (exists $symbol_table->{$name}) {
							die "fun redeclared as var" if (get_symbol_attr($name, 'type') ne $type);
						} else {
							$symbol_table->{$name} = {
								type => $type,
								attrs => ::StaticAttrs(::NoInitializer(), 1)
							};
						}
					} elsif ($storage->{tag} eq 'Static') {
						my $init_val;
						if (not defined $init) {
							$init_val = ::Initial(0);
						} elsif (my $const = ::extract($init, 'ConstantExpr')) {
							$init_val = const_to_initval($const, $type);
						} else {
							die "non-constant initializer on local static var";
						}
						$symbol_table->{$name} = {
							type => $type,
							attrs => ::StaticAttrs($init_val, 0)
						};
					} else {
						$symbol_table->{$name} = {
							type => $type,
							attrs => ::LocalAttrs()
						};
						if (defined $init) {
							check_types($init, $node);
						}
					}
				}
			}
			with (FunctionCall $name $args $type) {
				my ($param_types, $ret_type) = ::extract_or_die(get_symbol_attr($name, 'type'), 'FunType');
				die "wrong number of args: $name" if (@$param_types != @$args);
				my @converted_args;
				while (my ($i, $arg) = each @$args) {
					check_types($arg, $node);
					push(@converted_args, convert_type($arg, $param_types->[$i]));
				}	
				$node->{values}[1] = \@converted_args;
				set_type($node, $ret_type);
			}
			with (Var $name $type) {
				my $actual_type = get_symbol_attr($name, 'type');
				die "is not var: $name" if ($actual_type->{tag} eq 'FunType');
				set_type($node, $actual_type);
			}
			with (ConstantExpr $const) {
				if ($const->{tag} eq 'ConstInt') { 
					set_type($node, ::Int());
				} elsif ($const->{tag} eq 'ConstLong') { 
					set_type($node, ::Long());
			   	} else { 
					die "unknown const type $const";
			   	}
			}
			with (Cast $expr $type) {
				check_types($expr, $node);
				set_type($node, $type);
			}
			with (Unary $op $expr $type) {
				check_types($expr, $node);
				if ($op->{tag} eq 'Not') { 
					set_type($node, ::Int());
			   	} else { 
					set_type($node, get_type($expr)); 
				}
			}
			with (Binary $op $e1 $e2 $type) {
				check_types($e1, $node);
				check_types($e2, $node);
				if (::is_one_of($op, 'And', 'Or')) {
					set_type($node, ::Int());
				} else {
					my $common_type = get_common_type(get_type($e1), get_type($2));
					$node->{values}[1,2] = (convert_type($e1, $common_type), convert_type($e2, $common_type));
					if (::is_one_of($op, 'Add', 'Subtract', 'Multiply', 'Divide', 'Remainder')) {
						set_type($node, $common_type);
					} else {
						set_type($node, ::Int());
					}
				}
			} 
			with (Assignment $lhs $rhs $type) {
				check_types($lhs, $node);
				check_types($rhs, $node);
				my $left_type = get_type($lhs);
				$node->{values}[1] = convert_type($rhs, $left_type);
				set_type($node, $left_type);
			}
			with (Conditional $cond $then $else $type) {
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
		} 
		default {
			check_types($_, $node) for $node->{values}->@*;
		}	
	} elsif (ref($node) eq 'ARRAY') {
		check_types($_, $parent_node) for $node->@*;
	}
}

sub get_symbol_attr {
	my ($symbol, $attr_name) = @_;
	return $symbol_table->{$symbol}{type} if ($attr_name eq 'type');
	my $res;
	match ($symbol_table->{$symbol}{attrs}) {
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
			die "cant get attribute '$attr_name' of $symbol in " . $symbol_table->{$symbol}{attrs};
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
