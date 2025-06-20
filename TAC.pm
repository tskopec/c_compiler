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
		with (Binary $op $exp1 $exp2) {
			my $binop = convert_binop($op);
			my $src1 = emit_TAC($exp1, $instructions);
			my $src2 = emit_TAC($exp2, $instructions);
			my $dst = ::TAC_Variable(temp_name());
			push @$instructions, ::TAC_Binary($binop, $src1, $src2, $dst);
			return $dst;
		}
	}
}

# TODO nahradit evalem mozna? nezpomali to?
sub convert_unop {
	my $op = shift;
	match ($op) {
		with (Complement)	{ return ::TAC_Complement }
		with (Negate)		{ return ::TAC_Negate }
		default				{ die "unknown un op $op" }
	}	
}

sub convert_binop {
	my $op = shift;
	match ($op) {
		 with (Add)			{ return ::TAC_Add }
		 with (Subtract)	{ return ::TAC_Subtract }
		 with (Multiply)	{ return ::TAC_Multiply }
		 with (Divide)		{ return ::TAC_Divide }
		 with (Modulo)		{ return ::TAC_Modulo }
		 default			{ die "unknown bin op $op" }
	}
}

sub temp_name {
	state $n = 0;
	return "tmp." . $n++;
}

1;

