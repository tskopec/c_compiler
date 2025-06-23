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
		with (Function $name $body) {
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
			my $dst = ::TAC_Variable(temp_name());
			if ($op->{tag} eq 'And') {
				my ($false_label, $end_label) = labels(qw(false end));
				my $src1 = emit_TAC($exp1, $instructions);
				push @$instructions, ::TAC_JumpIfZero($src1, $false_label);
				my $src2 = emit_TAC($exp2, $instructions);
				push(@$instructions, ::TAC_JumpIfZero($src2, $false_label),
									 ::TAC_Copy(::TAC_Constant(1), $dst),
									 ::TAC_Jump($end_label),
									 ::TAC_Label($false_label),
									 ::TAC_Copy(::TAC_Constant(0), $dst),
									 ::TAC_Label($end_label));
			} elsif ($op->{tag} eq 'Or') {
				my ($true_label, $end_label) = labels(qw(true end));
				my $src1 = emit_TAC($exp1, $instructions);
				push @$instructions, ::TAC_JumpIfNotZero($src1, $true_label);
				my $src2 = emit_TAC($exp2,  $instructions);
				push(@$instructions, ::TAC_JumpIfNotZero($src2, $true_label),
									 ::TAC_Copy(::TAC_Constant(0), $dst),
									 ::TAC_Jump($end_label),
									 ::TAC_Label($true_label),
									 ::TAC_Copy(::TAC_Constant(1), $dst),
									 ::TAC_Label($end_label));
			} else {
				my $binop = convert_binop($op);
				my $src1 = emit_TAC($exp1, $instructions);
				my $src2 = emit_TAC($exp2, $instructions);
				push @$instructions, ::TAC_Binary($binop, $src1, $src2, $dst);
			}
			return $dst;
		}
	}
}

# TODO nahradit evalem mozna? nezpomali to?
sub convert_unop {
	my $op = shift;
	state $map = {
		Complement => ::TAC_Complement(),
		Negate => ::TAC_Negate(),
		Not => ::TAC_Not(),
	};
	return $map->{$op->{tag}} // die "unknown un op $op";
}

sub convert_binop {
	my $op = shift;
	state $map = {
		 Add => ::TAC_Add(),
		 Subtract => ::TAC_Subtract(),
		 Multiply => ::TAC_Multiply(),
		 Divide => ::TAC_Divide(),
		 Modulo => ::TAC_Modulo(),
		 And => ::TAC_And(),
		 Or => ::TAC_Or(),
		 Equal => ::TAC_Equal(),
		 NotEqual => ::TAC_NotEqual(),
		 LessThan => ::TAC_LessThan(),
		 LessOrEqual => ::TAC_LessOrEqual(),
		 GreaterThan => ::TAC_GreaterThan(),
		 GreaterOrEqual => ::TAC_GreaterOrEqual(),
	};
	return $map->{$op->{tag}} //  die "unknown bin op $op";
}

sub temp_name {
	return "tmp." . $::global_counter++;
}

sub labels {
	return map { "label_${_}_" . $global_counter } @_;
	$global_counter++;
}

1;

