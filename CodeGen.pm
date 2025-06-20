package CodeGen;
use strict;
use warnings;
use feature qw(say isa);
use List::Util qw(min);
use Types::Algebraic;


sub translate_to_ASM {
	my $node = shift;
	match ($node) {
		with (TAC_Program $declarations) {
			return ::ASM_Program([map { translate_to_ASM($_) } @$declarations]);
		}
		with (TAC_Function $ident $instructions) {
			return ::ASM_Function(
				$ident,
				[ map { translate_to_ASM($_) } @$instructions ]);
		}
		with (TAC_Return $value) {
			return (::ASM_Mov(translate_to_ASM($value), ::ASM_Reg(::AX())),
					::ASM_Ret());
		}
		with (TAC_Unary $op $src $dst) {
			my $asm_dst = translate_to_ASM($dst);
			return (::ASM_Mov(translate_to_ASM($src), $asm_dst),
					::ASM_Unary(convert_unop($op), $asm_dst));
		}
		with (TAC_Binary $op $src1 $src2 $dst) {
			my $asm_dst = translate_to_ASM($dst);
			if ((my $is_div = $op->{tag} eq 'TAC_Divide') || $op->{tag} eq 'TAC_Modulo') {
				return (
				::ASM_Mov(translate_to_ASM($src1), ::ASM_Reg(::AX())),
				::ASM_Cdq(),
				::ASM_Idiv(translate_to_ASM($src2)),
				::ASM_Mov(::ASM_Reg($is_div ? ::AX() : ::DX()), $asm_dst));
			} else {
				return (::ASM_Mov(translate_to_ASM($src1), $asm_dst),
						::ASM_Binary(convert_binop($op), translate_to_ASM($src2), $asm_dst));
			}
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

sub fix_up {
	my $program = shift;
	for my $declaration ($program->{values}[0]->@*) {
		match ($declaration) {
			with (ASM_Function $name $instructions) {
				replace_pseudo($declaration);
				fix_instr($declaration);
			}
			default { die "unknown declaration $declaration" }
		}
	}
}

sub replace_pseudo {
	my $function = shift;
	my $offsets = {}, my $process_node;
	$process_node = sub {
		my $node = shift;
		match ($node) {
			with (ASM_Pseudo $id) {
				unless (exists $offsets->{$id}) {
					$offsets->{$id} = -4 * (scalar(%$offsets) + 1);
				}
				return ::ASM_Stack($offsets->{$id});
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
	my ($name, $instructions) = ::extract_or_die($function, 'ASM_Function');
	unshift(@$instructions, ::ASM_AllocateStack(abs min(values %$offsets)));
}

sub fix_instr {
	my $function = shift;
	my $fix = sub {
		my $instruction = shift;
		if (my ($op, $src, $dst) = ::extract($instruction, 'ASM_Binary')) {
			if ($op->{tag} eq 'ASM_Mult') {
				if ($dst->{tag} eq 'ASM_Stack') {
					return (::ASM_Mov($dst, ::ASM_Reg(::R11())),
							::ASM_Binary($op, $src, ::ASM_Reg(::R11())),
							::ASM_Mov(::ASM_Reg(::R11()), $dst));
				}
			} elsif ($op->{tag} eq 'ASM_Add' || $op->{tag} eq 'ASM_Sub') {
				if ($src->{tag} eq 'ASM_Stack' && $dst->{tag} eq 'ASM_Stack') {
					return (::ASM_Mov($src, ::ASM_Reg(::R10())),
							::ASM_Binary($op, ::ASM_Reg(::R10()), $dst));
				}
			}
		} elsif (my ($src, $dst) = ::extract($instruction, 'ASM_Mov')) {
			if ($src->{tag} eq 'ASM_Stack' && $dst->{tag} eq 'ASM_Stack') {
				return (::ASM_Mov($src, ::ASM_Reg(::R10())),
						::ASM_Mov(::ASM_Reg(::R10()), $dst));
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
	my ($name, $instructions) = ::extract_or_die($function, 'ASM_Function');
	splice(@$instructions, 0, @$instructions, (map { $fix->($_) } @$instructions));
}

sub emit_code {
	my $node = shift;
	match ($node) {
		with (ASM_Program $declarations) {
			my $code = join "", map { emit_code($_) } @$declarations;
			$code .= '.section .note.GNU-stack,"",@progbits' . "\n"; 
			return $code;
		}
		with (ASM_Function $name $instructions) {
			my $code = "\t.globl $name\n";
			$code .= "$name:\n";
			$code .= "\tpushq %rbp\n";
			$code .= "\tmovq %rsp, %rbp\n";
			$code .= join "", map { emit_code($_) } @$instructions;
			return $code;
		} 
		with (ASM_Mov $src $dst) {
			return "\tmovl " . emit_code($src) . ", " . emit_code($dst) . "\n";
		}
		with (ASM_Ret) {
			my $code = "\tmovq %rbp, %rsp\n";
			$code .=   "\tpopq %rbp\n";
			$code .=   "\tret\n";
			return $code;
		}
		with (ASM_Unary $operator $operand) {
			return emit_code($operator) . " " . emit_code($operand) . "\n";
		}
		with (ASM_Binary $operator $src $dst) {
			return emit_code($operator) . " " . emit_code($src) . ", " . emit_code($dst) . "\n";
		}
		with (ASM_Idiv $operand) {
			return "\tidivl " . emit_code($operand) . "\n";
		}
		with (ASM_Cdq) {
			return "\tcdq\n";
		}
		with (ASM_AllocateStack $bytes) {
			return "\tsubq \$$bytes, %rsp\n";
		}
		with (ASM_Neg) {
			return "\tnegl";
		}
		with (ASM_Not) {
			return "\tnotl";
		}
		with (ASM_Add) {
			return "\taddl";
		}
		with (ASM_Sub) {
			return "\tsubl";
		}
		with (ASM_Mult) {
			return "\timull";
		}
		with (ASM_Reg $reg) {
			if ($reg->{tag} eq 'AX') { return "%eax" }
			elsif ($reg->{tag} eq 'DX') { return "%edx" }
			elsif ($reg->{tag} eq 'R10') { return "%r10d" }
			elsif ($reg->{tag} eq 'R11') { return "%r11d" }
			else { die "unknown register $reg" }
		}
		with (ASM_Stack $offset) {
			return "$offset(%rbp)";
		}
		with (ASM_Imm $val) {
			return "\$$val";
		}
		default { die "unknown asm node $node"}
	}
}
1;
