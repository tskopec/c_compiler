package TypeUtils;
use strict;
use warnings;
use feature qw(signatures);

use ADT::AlgebraicTypes qw(:AST :I :T);

use base 'Exporter';
our @EXPORT_OK = qw(MAX_ULONG MAX_LONG MAX_UINT MAX_INT get_type get_common_type get_int_type_rank is_signed convert_type
	types_equal const_to_initval);

use constant MAX_ULONG => 2 ** 64;
use constant MAX_LONG => 2 ** 63 - 1;
use constant MAX_UINT => 2 ** 32;
use constant MAX_INT => 2 ** 31 - 1;

sub get_common_type {
	my ($t1, $t2) = @_;
	return $t1 if ($t1->same_type_as($t2));
	my ($rank1, $rank2) = (get_int_type_rank($t1), get_int_type_rank($t2));
	if ($rank1 == $rank2) {
		return is_signed($t1) ? $t1 : $t2;
	} else {
		return $rank1 > $rank2 ? $t1 : $t2;
	}
}

sub get_int_type_rank {
	my $type = shift;
	return $type->match({
		"T_Long, T_ULong" => sub() { return 2 },
		"T_Int, T_UInt" => sub() { return 1 },
		default => sub() { die "no rank for type $type" }
	});
}

sub is_signed {
	my $type = shift;
	return ($type->{':tag'} =~ /^T_U/) ? 0 : 1;
}

sub convert_type {
	my ($expr, $type) = @_;
	return $type->same_type_as($expr->get('type')) ? $expr : AST_Cast($expr, $type);
}

sub types_equal {
	my ($t1, $t2) = @_;
	if ($t1->same_type_as($t2)) {
		if ($t1->is('T_FunType')) {
			my ($param_types1, $ret_type1) = $t1->values_in_order('T_FunType');
			my ($param_types2, $ret_type2) = $t2->values_in_order('T_FunType');
			return 0 if (@$param_types1 != @$param_types2 || $ret_type1 ne $ret_type2);
			return not grep { not $param_types1->[$_]->same_type_as($param_types2->[$_]) } (0 .. $#$param_types1);
		}
		return 1;
	}
	return 0;
}

sub const_to_initval {
	my ($const, $type) = @_;
	my $val = $const->get('val');
	return I_Initial($type->match({
		T_Int => sub() {
			return I_IntInit($val & 0xffffffff);
		},
		T_UInt => => sub() {
			return I_UIntInit($val & 0xffffffff);
		},
		T_Long => sub() {
			return I_LongInit($val <= MAX_LONG ? $val : die "integer $val too large for long");
		},
		T_ULong => sub() {
			return I_ULongInit($val <= MAX_ULONG ? $val : die "integer $val too large for ulong");
		},
		default => sub() {
			die "bad type: $type";
		}
	}));
}

sub get_type {
	my $val = shift;
	return $val->match({
		TAC_Constant => sub($const) {
			return get_type_of_constant($const);
		},
		TAC_Variable => => sub($name) {
			return $Semantics::symbol_table{$name}->{type};
		},
		default => sub { die "unknown type: $val" }
	});
}

sub get_type_of_constant {
	my $c = shift;
	return $c->match({
		C_ConstInt => T_Int(),
		C_ConstUInt => T_UInt(),
		C_ConstLong => T_Long(),
		C_ConstULong => T_ULong(),
		default => => sub() { die "unknown constant type $c" }
	});
}

1;