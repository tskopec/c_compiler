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
			with (FunDeclaration $name $params $body) {
				resolve_fun_declaration_ids($decl, $ids_map);
			}
			default { die "unknown declaration: $decl" }
		}
	}
}

sub resolve_fun_declaration_ids {
	my ($fun, $ids_map) = @_;
	my ($name, $params, $body) = ::extract_or_die($fun, 'FunDeclaration');
	if (exists $ids_map->{$name}) {
		my $previous_entry = $ids_map->{$name};
		if ($previous_entry->{from_this_scope} && !$previous_entry->{has_linkage}) {
			die "duplicate function declaration $name";
		}
	}
	$ids_map->{$name} = { uniq_name => $name, from_this_scope => 1, has_linkage => 1 };
	my $inner_ids_map = make_inner_scope_map($ids_map);
	resolve_var_declaration_ids($_, $inner_ids_map) for @$params;
   	if (defined $body) {
		my ($items) = ::extract($body, 'Block');
		resolve_block_item_ids($_, $inner_ids_map) for @$items;
	}
}

sub resolve_var_declaration_ids {
	my ($declaration, $ids_map) = @_;
	my ($name, $init) = ::extract_or_die($declaration, 'VarDeclaration');
	if (exists($ids_map->{$name}) && $ids_map->{$name}{from_this_scope}) {
		die "duplicate var $name";
	}
	$declaration->{values}[0] = unique_var_name($name);
	$ids_map->{$name} = { uniq_name => $declaration->{values}[0], from_this_scope => 1, has_linkage => 0 };
	resolve_expr_ids($init, $ids_map) if defined $init;
}

sub resolve_block_item_ids {
	my ($item, $ids_map) = @_;
	match ($item) {
		with (VarDeclaration $name $init) {
			resolve_var_declaration_ids($item, $ids_map);
		}
		with (FunDeclaration $name $params $body) {
			die "local fun definition: $name" if defined $body;
			resolve_fun_declaration_ids($item, $ids_map);
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
				resolve_var_declaration_ids($init, $new_idents);
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
		with (ConstantExp $val) {;}
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
	my ($node) = @_;
	if ($node isa Types::Algebraic::ADT) {
		match ($node) {
			with (VarDeclaration $name $init) {
				$symbol_table->{$name} = { type => ::Int() };
			}
			with (FunDeclaration $name $params $body) {
				my $type = ::FunType(scalar @$params);
				my $has_body = defined $body;
				my $already_defined = 0;

				if (exists $symbol_table->{$name}) {
					$already_defined = $symbol_table->{$name}{defined};
					die "incompatible fun declarations: $name" if ($symbol_table->{$name}{type} ne $type);
					die "fun defined multiple times: $name" if ($already_defined && $has_body);
				}
				$symbol_table->{$name} = { 
					type => ::FunType(scalar @$params),
					defined => ($already_defined || $has_body) 
				};
				if ($has_body) {
					$symbol_table->{$_} = ::Int() for @$params;
				}
			}
			with (FunctionCall $name $args) {
				my $type = $symbol_table->{$name}{type};
				die "is not function: $name" if ($type->{tag} ne 'FunType');
				die "wrong number of args: $name" if ($type->{values}[0] ne (scalar @$args));
				check_types($_) for @$args;	
			}
			with (Var $name) {
				die "is not var: $name" if ($symbol_table->{$name}{type} ne ::Int());
			}
		}	
		check_types($_) for $node->{values}->@*;
	} elsif (ref($node) eq 'ARRAY') {
		check_types($_) for $node->@*;
	}
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
