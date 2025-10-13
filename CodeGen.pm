package CodeGen;

use strict;
use warnings;
use feature qw(say isa state current_sub);
use List::Util qw(min);
use Types::Algebraic;
use Semantics;

my @arg_regs = (::DI(), ::SI(), ::DX(), ::CX(), ::R8(), ::R9());

### FIRST PASS ###
sub translate_to_ASM {
	my $node = shift;
	match ($node) {
		with (TAC_Program $declarations) {
			return ::ASM_Program([ map { translate_to_ASM($_) } @$declarations]);
		}
		with (TAC_Function $ident $global $params $instructions) {
			my $move_to_stack = sub {
				my $param_i = shift;
				my $src = ($param_i <= $#arg_regs) 
					? ::ASM_Reg($arg_regs[$param_i])
					: ::ASM_Stack(16 + 8 * ($param_i - @arg_regs));
				::ASM_Mov($src, ::ASM_Pseudo($params->[$param_i]));
			};
			return ::ASM_Function(
				$ident,
				$global,
				[ (map { $move_to_stack->($_) } (keys @$params)),
				  (map { translate_to_ASM($_) } @$instructions)	]
			);
		}
		with (TAC_StaticVariable $name $global $type $init) {
			# TODO return ::ASM_StaticVariable($name, $global, $init);
		}
		with (TAC_Return $value) {
			return (::ASM_Mov(translate_to_ASM($value), ::ASM_Reg(::AX())),
					::ASM_Ret());
		}
		with (TAC_Unary $op $src $dst) {
			my $asm_dst = translate_to_ASM($dst);
			if ($op->{tag} eq 'TAC_Not') {
				return (::ASM_Cmp(::ASM_Imm(0), translate_to_ASM($src)),
						::ASM_Mov(::ASM_Imm(0), $asm_dst),
						::ASM_SetCC(::E(), $asm_dst));
			}
			return (::ASM_Mov(translate_to_ASM($src), $asm_dst),
					::ASM_Unary(convert_unop($op), $asm_dst));
		}
		with (TAC_Binary $op $src1 $src2 $dst) {
			my $asm_dst = translate_to_ASM($dst);
			my $asm_type = asm_type_of($src1);
			if (-1 != (my $i = ::index_of_in($op, qw(TAC_Divide TAC_Modulo)))) {
				return (::ASM_Mov(translate_to_ASM($src1), ::ASM_Reg(::AX())),
						::ASM_Cdq(),
						::ASM_Idiv(translate_to_ASM($src2)),
						::ASM_Mov(::ASM_Reg((::AX(), ::DX())[$i]), $asm_dst));
			} elsif (-1 != (my $i = ::index_of_in($op, qw(TAC_Equal TAC_NotEqual TAC_LessThan TAC_LessOrEqual TAC_GreaterThan TAC_GreaterOrEqual)))) {
				return (::ASM_Cmp(translate_to_ASM($src2), translate_to_ASM($src1)),
						::ASM_Mov(::ASM_Imm(0), $asm_dst),
						::ASM_SetCC((::E(), ::NE(), ::L(), ::LE(), ::G(), ::GE())[$i], $asm_dst));
			} else {
				return (::ASM_Mov(translate_to_ASM($src1), $asm_dst),
						::ASM_Binary(convert_binop($op), translate_to_ASM($src2), $asm_dst));
			}
		}
		with (TAC_JumpIfZero $val $target) {
			return (::ASM_Cmp(::ASM_Imm(0), translate_to_ASM($val)),
					::ASM_JmpCC(::E(), $target));
		}
		with (TAC_JumpIfNotZero $val $target) {
			return (::ASM_Cmp(::ASM_Imm(0), translate_to_ASM($val)),
					::ASM_JmpCC(::NE(), $target));
		}
		with (TAC_Jump $target) {
			return ::ASM_Jmp($target);
		}
		with (TAC_Label $ident) {
			return ::ASM_Label($ident);
		}
		with (TAC_Copy $src $dst) {
			return ::ASM_Mov(translate_to_ASM($src), translate_to_ASM($dst));
		}
		with (TAC_FunCall $ident $args $dst) {
			my (@instructions, @reg_args, @stack_args);
			(@reg_args[0..($#$args < 5 ? $#$args : 5)], @stack_args) = @$args;
			my $stack_padding = 8 * (@stack_args % 2);
			if ($stack_padding) {
				push(@instructions, ::ASM_AllocateStack($stack_padding));
			}	
			while (my ($i, $tac_arg) = each @reg_args) {
				my $asm_arg = translate_to_ASM($tac_arg);
				push(@instructions, ::ASM_Mov($asm_arg, ::ASM_Reg($arg_regs[$i])));
			}
			for my $tac_arg (reverse @stack_args) {
				my $asm_arg = translate_to_ASM($tac_arg);
				if (::is_one_of($asm_arg, qw(ASM_Imm ASM_Reg))) {
					push(@instructions, ::ASM_Push($asm_arg));
				} else {
					push(@instructions, (::ASM_Mov($asm_arg, ::ASM_Reg(::AX())),
										 ::ASM_Push(::ASM_Reg(::AX()))));
				}
			}
			push(@instructions, ::ASM_Call($ident));
			my $remove_bytes = 8 * @stack_args + $stack_padding;
			if ($remove_bytes) {
				push(@instructions, ::ASM_DeallocateStack($remove_bytes));
			}
			push(@instructions, ::ASM_Mov(::ASM_Reg(::AX()), translate_to_ASM($dst)));
			return @instructions;
		}
		with (TAC_Constant $int) {
			return ::ASM_Imm($int);
		}
		with (TAC_Variable $ident) {
			return ::ASM_Pseudo($ident);
		}
		default { die "unknown TAC $node" }
	}
}

sub convert_unop {
	my $op = shift;
	match ($op) {
		with (TAC_Complement)	{ return ::ASM_Not }
		with (TAC_Negate)		{ return ::ASM_Neg }
		default					{ die "unknown op $op" }
	}	
}

sub convert_binop {
	my $op = shift;
	match ($op) {
		 with (TAC_Add)			{ return ::ASM_Add }
		 with (TAC_Subtract)	{ return ::ASM_Sub }
		 with (TAC_Multiply)	{ return ::ASM_Mult }
		 default				{ die "unknown bin op $op" }
	}	
}

sub asm_type_of {
	my $tac_val = shift;
	match ($tac_val) {
		with (TAC_Constant $const) {
				
		}
		with (TAC_Variable $name) {
			return $Semantics::symbol_table->{$name}{type};
		}
		default {
			die "unknown val $tac_val";
		}
	}
}


### SECOND PASS ###
sub fix_up {
	my $program = shift;
	for my $declaration ($program->{values}[0]->@*) {
		match ($declaration) {
			with (ASM_Function $name $global $instructions) {
				replace_pseudo($declaration);
				fix_instr($declaration);
			}
			with (ASM_StaticVariable $name $global $type $init) {;}
			default { die "not a declaration: $declaration" }
		}
	}
}

sub replace_pseudo {
	my ($function, $offsets) = (shift(), {});
	my $process_node;
	$process_node = sub {
		my $node = shift;
		match ($node) {
			with (ASM_Pseudo $ident) {
				if (exists $Semantics::symbol_table->{$ident}
				   	&& $Semantics::symbol_table->{$ident}{attrs}{tag} eq 'StaticAttrs') {
					return ::ASM_Data($ident);
				}
				$offsets->{$ident} //= -8 * scalar(%$offsets); # bacha, //= zpusobi autovivifikaci -> scalar na prave strane vrati velikost uz vcetne noveho prvku
				return ::ASM_Stack($offsets->{$ident});
			}
			default { 
				for my $val ($node->{values}->@*) {
					if ($val isa Types::Algebraic::ADT) {
						$val = $process_node->($val);
					} elsif (ref($val) eq 'ARRAY') {
						$val = [ map { $process_node->($_) } @$val ];
					}
				}
				return $node;
			}
		}
	};
	$process_node->($function);
	my ($name, $global, $instructions) = ::extract_or_die($function, 'ASM_Function');
	my $max_offset = abs(min(values %$offsets));
	unshift(@$instructions, ::ASM_AllocateStack($max_offset + ($max_offset % 16))); # 16 byte aligned
}

sub fix_instr {
	my $function = shift;
	my $fix = sub {
		my $instruction = shift;
		if (my ($op, $src, $dst) = ::extract($instruction, 'ASM_Binary')) {
			if ($op->{tag} eq 'ASM_Mult') {
				if (is_mem_addr($dst)) {
					return (::ASM_Mov($dst, ::ASM_Reg(::R11())),
							::ASM_Binary($op, $src, ::ASM_Reg(::R11())),
							::ASM_Mov(::ASM_Reg(::R11()), $dst));
				}
			} elsif ($op->{tag} eq 'ASM_Add' || $op->{tag} eq 'ASM_Sub') {
				if (is_mem_addr($src) && is_mem_addr($dst)) {
					return (::ASM_Mov($src, ::ASM_Reg(::R10())),
							::ASM_Binary($op, ::ASM_Reg(::R10()), $dst));
				}
			}
		} elsif (my ($src, $dst) = ::extract($instruction, 'ASM_Mov')) {
			if (is_mem_addr($src) && is_mem_addr($dst)) {
				return (::ASM_Mov($src, ::ASM_Reg(::R10())),
						::ASM_Mov(::ASM_Reg(::R10()), $dst));
			}
		} elsif (my ($src, $dst) = ::extract($instruction, 'ASM_Cmp')) {
			if (is_mem_addr($src) && is_mem_addr($dst)) {
				return (::ASM_Mov($src, ::ASM_Reg(::R10())),
						::ASM_Cmp(::ASM_Reg(::R10()), $dst));
			} elsif ($dst->{tag} eq 'ASM_Imm') {
				return (::ASM_Mov($dst, ::ASM_Reg(::R11())),
						::ASM_Cmp($src, ::ASM_Reg(::R11())));
			}
		}
		elsif (my ($operand) = ::extract($instruction, 'ASM_Idiv')) {
			if ($operand->{tag} eq 'ASM_Imm') {
				return (::ASM_Mov($operand, ::ASM_Reg(::R10())),
						::ASM_Idiv(::ASM_Reg(::R10())));
			}
		}
		return $instruction;
	};
	my ($name, $global, $instructions) = ::extract_or_die($function, 'ASM_Function');
	splice(@$instructions, 0, $#$instructions + 1, ( map { $fix->($_) } @$instructions ));
}

sub is_mem_addr {
	return ::is_one_of(shift(), 'ASM_Stack', 'ASM_Data');
}

1;
