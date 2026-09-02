package TypeUtils;
use strict;
use warnings;
use feature qw(signatures isa state);

use ADT::AlgebraicTypes qw(:AST :INI :SI :T :C is_ADT);

use base 'Exporter';
our @EXPORT_OK = qw(MAX_ULONG MAX_LONG MAX_UINT MAX_INT get_type_of_TAC get_common_type get_common_pointer_type
	get_int_type_rank is_signed is_arithmetic is_integer is_character size_of get_base_type convert_type convert_as_if_by_assignment types_equal create_const
	flatten_init get_static_init);

use constant MAX_ULONG => 2 ** 64;
use constant MAX_LONG => 2 ** 63 - 1;
use constant MAX_UINT => 2 ** 32;
use constant MAX_INT => 2 ** 31 - 1;

sub get_common_type {
	my ($t1, $t2) = @_;
	$t1 = T_Int if (is_character($t1));
	$t2 = T_Int if (is_character($t2));
	return $t1 if ($t1->same_type_as($t2));
	return T_Double if $t1->is('T_Double') || $t2->is('T_Double');
	my ($rank1, $rank2) = (get_int_type_rank($t1), get_int_type_rank($t2));
	if ($rank1 == $rank2) {
		return is_signed($t1) ? $t2 : $t1;
	} else {
		return $rank1 > $rank2 ? $t1 : $t2;
	}
}

sub get_common_pointer_type {
	my ($t1, $t2) = map { $_->get('type') } @_;
	return $t1 if ($t1 eq $t2);
	return T_Pointer($t1) if (is_null_pointer_const($_[0]));
	return T_Pointer($t2) if (is_null_pointer_const($_[1]));
	die "incompatible types: " . join(" - ", @_);
}

sub is_null_pointer_const {
	my $expr = shift;
	return 0 unless $expr->is('AST_ConstantExpr');
	return 0 if $expr->get('constant')->is('C_ConstDouble');
	return $expr->get('constant')->get('val') == 0;
}

sub get_int_type_rank {
	my $type = shift;
	return $type->match({
		"T_Long, T_ULong, T_Pointer" => 2,
		"T_Int, T_UInt" => 1,
		default => sub {
			die "no rank for type $type"
		}
	});
}

sub is_signed {
	return is_one_of(\@_, state $wanted = ['T_Int', 'T_Long', 'T_Double', 'T_Char', 'T_SChar']);
}

sub is_arithmetic {
	return is_one_of(\@_, state $wanted = ['T_Int', 'T_UInt', 'T_Long', 'T_ULong', 'T_Char', 'T_SChar', 'T_UChar', 'T_Double']);
}

sub is_integer {
	return is_one_of(\@_, state $wanted = ['T_Int', 'T_UInt', 'T_Long', 'T_ULong', 'T_Char', 'T_SChar', 'T_UChar']);
}

sub is_character {
	return is_one_of(\@_, state $wanted = ['T_Char', 'T_SChar', 'T_UChar']);
}

sub is_one_of {
	my ($types, $wanted) = @_;
	for my $type (@$types) {
		return 0 unless $type->is(@$wanted);
	}
	return 1;
}

sub size_of {
	my $type = shift;
	return $type->match({
		'T_Int, T_UInt, ASM_Longword' => 4,
		'T_Long, T_ULong, T_Double, T_Pointer, ASM_Quadword, ASM_Double' => 8,
		'T_Array' => sub($elem_type, $size) {
			return size_of($elem_type) * $size;
		},
		ASM_ByteArray => sub($size, $alignment) { return $size },
		default => sub { die "bad type $type" }
	});
}

sub get_base_type {
	my $type = shift;
	return $type->match({
		T_Array => sub($elem_type, $size) { return get_base_type($elem_type) },
		"T_Int, T_UInt, T_Long, T_ULong, T_Double, T_Pointer" => $type,
		default => sub { die "wtf type $type" }
	});
}

sub convert_type {
	my ($expr, $type) = @_;
	return $type->same_type_as($expr->get('type')) ? $expr : AST_Cast($expr, $type);
}

sub convert_as_if_by_assignment {
	my ($expr, $target_type) = @_;
	return $expr if ($expr->get('type') eq $target_type);
	if ((is_arithmetic($expr->get('type')) && is_arithmetic($target_type))
		|| (is_null_pointer_const($expr) && $target_type->is('T_Pointer'))) {
		return convert_type($expr, $target_type);
	}
	die "cant convert $expr to $target_type";
}

sub types_equal {
	my ($t1, $t2) = @_;
	return 0 unless $t1->same_type_as($t2);
	$t1->match({
		T_FunType => sub($param_types1, $ret_type1) {
			my ($param_types2, $ret_type2) = $t2->values_in_order('T_FunType');
			return 0 if (@$param_types1 != @$param_types2 || $ret_type1 ne $ret_type2);
			for my $i (0 .. $#$param_types1) {
				return 0 unless types_equal($param_types1->[$i], $param_types2->[$i]);
			}
			return 1;
		},
		T_Array => sub($to_type1, $size1) {
			return $size1 == $t2->get('size') && types_equal($to_type1, $t2->get('elem_type'));
		},
		T_Pointer => sub($to_type1) {
			return types_equal($to_type1, $t2->get('to_type'));
		},
		default => 1
	});
}

sub create_const {
	my ($type, $val) = @_;
	return $type->match({
		T_Int => sub { C_ConstInt($val) },
		T_UInt => sub { C_ConstUInt($val) },
		T_Long => sub { C_ConstLong($val) },
		T_ULong => sub { C_ConstULong($val) },
		T_Double => sub { C_ConstDouble($val) },
		T_Pointer => sub { C_ConstULong($val) },
		'T_Char, T_SChar' => sub { C_ConstChar($val) },
		T_UChar => sub { C_ConstUChar($val) },
		default => sub {
			die "bad type $type";
		}
	});
}

sub flatten_init {
	my $init = shift;
	return $init->match({
		AST_SingleInit => $init,
		AST_CompoundInit => sub($inits, $init_type) {
			return map { flatten_init($_) } @$inits;
		},
		default => sub { die "wtf" }
	});
}

sub get_static_init {
	my ($arg, $type) = @_;
	my $value = (is_ADT($arg, 'C_Constant'))
		? ($arg->is('C_ConstDouble') && !$type->is('T_Double'))
			? int($arg->get('val'))
			: $arg->get('val')
		: $arg;
	return $type->match({
		T_Int => sub() {
			SI_IntInit($value & 0xffffffff);
		},
		T_UInt => => sub() {
			SI_UIntInit($value & 0xffffffff);
		},
		T_Long => sub() {
			SI_LongInit($value <= MAX_LONG ? $value : die "integer $value too large for long");
		},
		T_ULong => sub() {
			SI_ULongInit($value <= MAX_ULONG ? $value : die "integer $value too large for ulong");
		},
		T_Pointer => sub($to_type) {
			SI_ULongInit($value == 0 ? $value : die "$value not null constant");
		},
		T_Double => sub() {
			SI_DoubleInit($value);
		},
		'T_Char, T_SChar' => sub() {
			SI_CharInit($value & 0xff);
		},
		T_UChar => sub() {
			SI_UCharInit($value & 0xff);
		},
		T_Array => sub($elem_type, $size) {
			die "not char array" unless is_character($elem_type);
			SI_StringInit($value, $size > length($value));
		},
		default => sub {
			die "unknown type: $type";
		}
	});
}

sub get_type_of_TAC {
	my $val = shift;
	return $val->match({
		TAC_Constant => sub($const) {
			return $const->match({
				C_ConstInt => T_Int,
				C_ConstUInt => T_UInt,
				C_ConstLong => T_Long,
				C_ConstULong => T_ULong,
				C_ConstDouble => T_Double,
				default => sub { die "unknown constant type $const" }
			});
		},
		TAC_Variable => sub($name) {
			return ($Semantics::symbol_table{$name} // die "unknown symbol $name")->{type};
		},
		default => sub { die "unknown type: $val" }
	});
}

1;