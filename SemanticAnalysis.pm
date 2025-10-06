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
	check_types($ast, undef);
	label_loops($ast);
}

### IDENTIFIER RESOLUTION ###
sub resolve_ids {
	my ($declarations) = ::extract_or_die(shift(), 'Program'); 
	my $ids_map = {};
	for my $decl (@$declarations) {
		match ($decl) {
			with (FunDeclaration $name $params $body $storage) {
				resolve_fun_declaration_ids($decl, $ids_map, 0);
			}
			with (VarDeclaration $name $init $storage) {
				resolve_top_level_var_declaration_ids($decl, $ids_map);
			}
			default { die "unknown declaration: $decl" }
		}
	}
}

sub resolve_fun_declaration_ids {
	my ($fun, $ids_map, $in_block_scope) = @_;
	my ($name, $params, $body, $storage) = ::extract_or_die($fun, 'FunDeclaration');
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
	my ($name, $init, $storage) = ::extract_or_die($decl, 'VarDeclaration');
	$ids_map->{$name} = { uniq_name => $name, from_this_scope => 1, has_linkage => 1};
}

sub resolve_local_var_declaration_ids {
	my ($declaration, $ids_map) = @_;
	my ($name, $init, $storage) = ::extract_or_die($declaration, 'VarDeclaration');
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
		with (VarDeclaration $name $init $storage) {
			resolve_local_var_declaration_ids($item, $ids_map);
		}
		with (FunDeclaration $name $params $body $storage) {
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
		with (Var $name) { $expr->{values}[0] = ($ids_map->{$name}{uniq_name} // die "undeclared variable $name"); }
		with (Unary $op $e) { resolve_expr_ids($e, $ids_map); }
		with (Binary $op $e1 $e2) { resolve_expr_ids($_, $ids_map) for ($e1, $e2); }
		with (Assignment $le $re) { 
			die "not a variable $le" if ($le->{tag} ne 'Var');
		   	resolve_expr_ids($_, $ids_map) for ($le, $re);
	   	}
		with (Conditional $cond $then $else) { resolve_expr_ids($_, $ids_map) for ($cond, $then, $else); }
		with (FunctionCall $name $args) {
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
	my ($node, $parent_node) = @_;
	if ($node isa Types::Algebraic::ADT) {
		match ($node) {
			with (FunDeclaration $name $params $body $storage) {
				my $type = ::FunType(scalar @$params);
				my $has_body = defined($body);
				my $already_defined = 0;
				my $global = $storage->{tag} ne 'Static';

				if (exists $symbol_table->{$name}) {
					$already_defined = getAttr($name, 'defined');
					die "incompatible fun declarations: $name" if (getAttr($name, 'type') ne $type);
					die "fun defined multiple times: $name" if ($already_defined && $has_body);
					die "static fun declaration after non-static" if (getAttr($name, 'global') && !$global);
					$global = getAttr($name, 'global');
				}
				$symbol_table->{$name} = { 
					type => ::FunType(scalar @$params),
					attrs => ::FunAttrs(
						($already_defined || $has_body),
						0+$global
					)
				};
				if ($has_body) {
					$symbol_table->{$_} = { type => ::Int(), attrs => ::LocalAttrs() } for @$params;
				}
			}
			with (VarDeclaration $name $init $storage) {
				my $is_file_scope = ($parent_node isa Types::Algebraic::ADT) && ($parent_node->{tag} eq 'Program');
				if ($is_file_scope) {
					my $init_val;
					if (!defined $init) {
						$init_val = $storage->{tag} eq 'Extern' ? ::NoInitializer() : ::Tentative();
					} elsif ($init->{tag} eq 'ConstantExpr') {
						$init_val = ::Initial($init->{values}[0]);
					} else {
						die "initializer must be constant";
					}
					my $global = $storage->{tag} ne 'Static';
					
					if (exists $symbol_table->{$name}) {
						die "already declared as fun" if (getAttr($name, 'type') ne ::Int());
						if ($storage->{tag} eq 'Extern') {
							$global = getAttr($name, 'global');
						} elsif (getAttr($name, 'global') != $global) {
							die "conflicting linkage, var $name";
						}

						my $prev_init = getAttr($name, 'init_value');
						if ($prev_init->{tag} eq 'Initial') {
							die "conflicting file scope var definitions: $name " if ($init_val->{tag} eq 'Initial');
							$init_val = $prev_init;
						} elsif ($init_val->{tag} ne 'Initial' && $prev_init->{tag} eq 'Tentative') {
							$init_val = ::Tentative();
						}
					}
					$symbol_table->{$name} = { 
						type => ::Int(),
						attrs => ::StaticAttrs($init_val, 0+$global)
					};	
				} else { # local var
					if ($parent_node isa Types::Algebraic::ADT && $parent_node->{tag} eq 'For' && defined($storage)) {
						die "for loop header var $name declaration with storage class";
					}
					if ($storage->{tag} eq 'Extern') {
						die "initalizing local extern variable" if (defined $init);
						if (exists $symbol_table->{$name}) {
							die "fun redeclared as var" if (getAttr($name, 'type') ne ::Int());
						} else {
							$symbol_table->{$name} = {
								type => ::Int(),
								attrs => ::StaticAttrs(::NoInitializer(), 1)
							};
						}
					} elsif ($storage->{tag} eq 'Static') {
						my $init_val;
						if (not defined $init) {
							$init_val = ::Initial(0);
						} elsif ($init->{tag} eq 'ConstantExpr') {
							$init_val = ::Initial($init->{values}[0]);
						} else {
							die "non-constant initializer on local static var";
						}
						$symbol_table->{$name} = {
							type => ::Int(),
							attrs => ::StaticAttrs($init_val, 0)
						};
					} else {
						$symbol_table->{$name} = {
							type => ::Int(),
							attrs => ::LocalAttrs()
						};
						if (defined $init) {
							check_types($init, $node);
						}
					}
				}
			}
			with (FunctionCall $name $args) {
				my $type = getAttr($name, 'type');
				die "is not function: $name" if ($type->{tag} ne 'FunType');
				die "wrong number of args: $name" if ($type->{values}[0] ne (scalar @$args));
				check_types($_, $node) for @$args;	
			}
			with (Var $name) {
				die "is not var: $name" if (getAttr($name, 'type') ne ::Int());
			}
		}	
		check_types($_, $node) for $node->{values}->@*;
	} elsif (ref($node) eq 'ARRAY') {
		check_types($_, $parent_node) for $node->@*;
	}
}

sub getAttr {
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
