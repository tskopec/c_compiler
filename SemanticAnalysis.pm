package SemanticAnalysis;

use strict;
use warnings;
use feature qw(say state isa);
use Types::Algebraic;

sub run {
	my $ast = shift;
	#	resolve_vars($ast);
	#	label_loops($ast, undef);
}

### VARIABLE RESOLUTION ###
#	sub resolve_vars {
#		my ($definitions) = ::extract_or_die(shift(), 'Program'); 
#		for my $def (@$definitions) {
#			match ($def) {
#				with (FunDeclaration $name $body) {
#					my ($items) = ::extract_or_die($body, 'Block');
#					my $var_map = {};
#					resolve_body_vars($_, $var_map) for (@$items); 
#				}
#				default { die "unknown def $def" }
#			}
#		}
#	}
#	
#	sub resolve_body_vars {
#		my ($item, $vars) = @_;
#		match ($item) {
#			with (Declaration $name $init) {
#				resolve_declaration_vars($item, $vars);
#			}
#			default {
#				resolve_statement_vars($item, $vars);
#			}
#		}
#	}
#	
#	sub resolve_declaration_vars {
#		my ($declaration, $vars) = @_;
#		my ($name, $init) = ::extract_or_die($declaration, 'Declaration');
#		if (exists($vars->{$name}) && $vars->{$name}{from_this_block}) {
#			die "duplicate var $name";
#		}
#		$declaration->{values}[0] = unique_var_name($name);
#		$vars->{$name} = { uniq_name => $declaration->{values}[0], from_this_block => 1 };
#		resolve_expr_vars($init, $vars) if defined $init;
#	}
#	
#	sub resolve_statement_vars {
#		my ($statement, $vars) = @_;
#		match ($statement) {
#			with (Return $e) { resolve_expr_vars($e, $vars); }
#			with (Expression $e) { resolve_expr_vars($e, $vars); }
#			with (Null) {;}
#			with (If $cond $then $else) {
#				resolve_expr_vars($cond, $vars);
#				resolve_statement_vars($then, $vars);
#				resolve_statement_vars($else, $vars) if defined $else;
#			}
#			with (Compound $block) {
#				my ($items) = ::extract_or_die($block, 'Block');
#				my $new_vars = copy_vars($vars);
#				resolve_body_vars($_, $new_vars) for @$items; 
#			}
#			with (While $cond $body $label) {
#				resolve_expr_vars($cond, $vars);
#				resolve_statement_vars($body, $vars);
#			} 
#			with (DoWhile $body $cond $label) {
#				resolve_statement_vars($body, $vars);
#				resolve_expr_vars($cond, $vars);
#			}
#			with (For $init $cond $post $body $label) {
#				my $new_vars = copy_vars($vars);
#				if (defined $init && $init->{tag} eq 'Declaration') {
#					resolve_declaration_vars($init, $new_vars);
#				} else {
#					resolve_opt_expr_vars($init, $new_vars);
#				}
#				resolve_opt_expr_vars($cond, $new_vars);
#				resolve_opt_expr_vars($post, $new_vars);
#				resolve_statement_vars($body, $new_vars);
#			}
#			with (Break $label) {;}
#			with (Continue $label) {;}
#			default { die "unknown statement $statement" }
#		}	   
#	}
#	
#	sub resolve_opt_expr_vars {
#		my ($expr, $vars) = @_;
#		resolve_expr_vars($expr, $vars) if defined $expr;
#	}
#	
#	sub resolve_expr_vars {
#		my ($expr, $vars) = @_;
#		match ($expr) {
#			with (ConstantExp $val) {;}
#			with (Var $name) { $expr->{values}[0] = ($vars->{$name}{uniq_name} // die "undeclared variable $name"); }
#			with (Unary $op $e) { resolve_expr_vars($e, $vars); }
#			with (Binary $op $e1 $e2) { resolve_expr_vars($_, $vars) for ($e1, $e2); }
#			with (Assignment $le $re) { 
#				die "not a variable $le" if ($le->{tag} ne 'Var');
#			   	resolve_expr_vars($_, $vars) for ($le, $re);
#		   	}
#			with (Conditional $cond $then $else) { resolve_expr_vars($_, $vars) for ($cond, $then, $else); }
#			default { die "unknown expression $expr" }
#		}
#	}
#	
#	sub unique_var_name {
#		return +shift . '.' . $::global_counter++;
#	}
#	
#	sub copy_vars {
#		my $original_vars = shift;
#		my $result = {};
#		while (my ($name_in_src, $properties) = each %$original_vars) {
#			$result->{$name_in_src} = {
#				uniq_name => $properties->{uniq_name},
#				from_this_block => 0
#			}
#		};
#		return $result;
#	}
#	
#	### LOOP LABELING ###
#	sub label_loops {
#		my ($node, $current_label) = @_;
#		if ($node isa Types::Algebraic::ADT) {
#			if (::is_one_of($node, 'While', 'DoWhile', 'For')) {
#				$current_label = new_loop_label();
#				$node->{values}[-1] = $current_label;
#			} elsif (::is_one_of($node, 'Break', 'Continue')) {
#				$node->{values}[0] = ($current_label // die("'" . lc($node->{tag}) . "' outside loop"));
#				return;
#			}
#			label_loops($_, $current_label) for $node->{values}->@*;
#		} elsif (ref($node) eq 'ARRAY') {
#			label_loops($_, $current_label) for $node->@*;
#		}
#	}
#	
#	sub new_loop_label {
#		return "_loop_" . $::global_counter++;
#	}

1;
