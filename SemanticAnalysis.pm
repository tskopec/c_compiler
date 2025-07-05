package SemanticAnalysis;
use strict;
use warnings;
use feature qw(say state);
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
				my $var_map = {};
				resolve_body_vars($_, $var_map) for (@$body); 
			}
		}
	}
}

sub resolve_body_vars {
	my ($item, $vars) = @_;
	match ($item) {
		with (S $statement) { 
			resolve_statement_vars($statement, $vars);
		}
		with (D $declaration) {
			my ($name, $init) = ::extract($declaration, 'Declaration');
			die "duplicate var $name" if exists $vars->{$name};
			$vars->{$name} = unique_var_name($name);
			$declaration->{values}[0] = $vars->{$name};
			resolve_expr_vars($init, $vars) if defined $init;
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
	}	   
}

sub resolve_expr_vars {
	my ($expr, $vars) = @_;
	match ($expr) {
		with (Var $name) { $expr->{values}[0] = ($vars->{$name} // die "undeclared variable $name"); }
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
