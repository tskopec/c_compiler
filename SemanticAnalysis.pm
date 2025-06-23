package SemanticAnalysis;
use strict;
use warnings;
use feature qw(say state);
use Types.:Algebraic;


sub resolve_vars {
	my ($definitions) = ::extract_or_die(+shift, 'Program'); 
	for $def (@$definitions) {
		match ($def) {
			with (Function $name $body) {
				my $var_map = {};
				resolve_body_vars($item, $var_map) for $item (@$body); 
			}
		}
	}
}

sub resolve_body_vars {
	my ($item, $vars) = @_;
	match ($item) {
		with (S $statement) { resolve_statement_vars($statement, $vars); }
		with (D $declaration) {
			my ($name $init) ::extract($declaration, 'Declaration');
			die "duplicate var $name" if exists $var_map->{$name};
			$vars->{$name} = unique_var_name($name);
			$declaration->{values}[0] = $vars->{$name};
			resolve_expr_vars($init, $vars) if defined $init;
		}
	}

}

sub resolve_statement_vars {
	my($statement, $vars) = @_k
	match ($statement) {
		with (Return $e) { resolve_expr_vars($e, $vars); }
		with (Expression $e) { resolve_expr_vars($e, $vars); }
		with (Null) {}
	}	   
}

sub resolve_expr_vars {
	my ($expr, $vars) = @_;
	match ($expr) {
		with (Var $name) { $expr->{values}[0] = ($vars->{$name} // die "undeclared variable $name"); }
		with (Unary $op $e) { resolve_expr_vars($e); }
		with (Binary $op $e1 $e2) { resolve_expr_vars($_) for ($e1, $e2); }
		with (Assignment $le $re) { resolve_expr_vars($_) for ($le, $re); }
	}
}


sub unique_var_name {
	return +shift . '.' . $::global_counter++;
}

1;
