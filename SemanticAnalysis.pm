package SemanticAnalysis;

use strict;
use warnings;
use feature qw(say state);
use List::Util qw(pairmap);
use Types::Algebraic;


sub run {
	my $ast = shift;
	resolve_vars($ast);
}

sub resolve_vars {
	my ($definitions) = ::extract_or_die(+shift, 'Program'); 
	for my $def (@$definitions) {
		match ($def) {
			with (Function $name $body) {
				my ($items) = ::extract_or_die($body, 'Block');
				my $var_map = {};
				resolve_body_vars($_, $var_map) for (@$items); 
			}
		}
	}
}

sub resolve_body_vars {
	my ($item, $vars) = @_;
	match ($item) {
		with (Declaration $name $init) {
			if (exists($vars->{$name}) && $vars->{$name}{from_this_block}) {
				die "duplicate var $name";
			}
			$item->{values}[0] = unique_var_name($name);
			$vars->{$name} = { uniq_name => $item->{values}[0], from_this_block => 1 };
			resolve_expr_vars($init, $vars) if defined $init;
		}
		default {
			resolve_statement_vars($item, $vars);
		}
	}
}

sub resolve_statement_vars {
	my ($statement, $vars) = @_;
	match ($statement) {
		with (Return $e) { resolve_expr_vars($e, $vars); }
		with (Expression $e) { resolve_expr_vars($e, $vars); }
		with (Null) {;}
		with (If $cond $then $else) {
			resolve_expr_vars($cond, $vars);
			resolve_statement_vars($then, $vars);
			resolve_statement_vars($else, $vars) if defined $else;
		}
		with (Compound $block) {
			my ($items) = ::extract_or_die($block, 'Block');
			my $block_vars = { pairmap { ($a, { uniq_name => $b->{uniq_name}, from_this_block => 0 }) } %$vars };
			resolve_body_vars($_, $block_vars) for @$items; 
		}
	}	   
}

sub resolve_expr_vars {
	my ($expr, $vars) = @_;
	match ($expr) {
		with (Var $name) { $expr->{values}[0] = ($vars->{$name}{uniq_name} // die "undeclared variable $name"); }
		with (Unary $op $e) { resolve_expr_vars($e, $vars); }
		with (Binary $op $e1 $e2) { resolve_expr_vars($_, $vars) for ($e1, $e2); }
		with (Assignment $le $re) { 
			die "not a variable $le" if ($le->{tag} ne 'Var');
		   	resolve_expr_vars($_, $vars) for ($le, $re);
	   	}
		with (Conditional $cond $then $else) { resolve_expr_vars($_, $vars) for ($cond, $then, $else); }
	}
}


sub unique_var_name {
	return +shift . '.' . $::global_counter++;
}

1;
