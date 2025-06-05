package TAC;
use strict;
use warnings;
use feature qw(say state);
use Types::Algebraic;


sub emit_TAC {
	my ($node, $instructions) = @_;
	match ($node) {
		with (Program $declarations) {
			return ::TAC_Program([ map { emit_TAC($_) } @$declarations ]);
		}
		with (FunctionDeclaration $name $body) {
			my $instructions = [];
			for my $stm (@$body) {
				emit_TAC($stm, $instructions);
			}
			return ::TAC_Function($name, $instructions);
		}
		with (Return $exp) {
			push(@$instructions, ::TAC_Return(emit_TAC($exp, $instructions)));
		}
		with (ConstantExp $val) {
			return ::TAC_Constant($val);
		}
		with (Unary $op $exp) {
			my $unop = convert_unop($op);
			my $src = emit_TAC($exp, $instructions);
			my $dst = ::TAC_Variable(temp_name());
			push @$instructions, ::TAC_Unary($unop, $src, $dst);	
			return $dst;
		}
	}
}

sub convert_unop {
	my $op = shift;
	match ($op) {
		with (Complement)	{ return ::TAC_Complement }
		with (Negate)		{ return ::TAC_Negate }
		default				{ die "unknown op $op" }
	}	
}


sub temp_name {
	state $n = 0;
	return "tmp." . $n++;
}

1;

