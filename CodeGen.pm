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
			return (::ASM_Mov(translate_to_ASM($src), translate_to_ASM($dst)),
					::ASM_Unary(convert_unop($op), translate_to_ASM($dst)));
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
		default				{ die "unknown op $op" }
	}	
}

sub fix_up {
	my $program = shift;
	for my $declaration ($program->{values}[0]->@*) {
		match ($declaration) {
			with (ASM_Function $name $instructions) {
				replace_pseudo($declaration);
				fix_movs($declaration);
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
	my ($name, $instructions) = ::extract('ASM_Function', $function);
	unshift(@$instructions, ::ASM_AllocateStack(abs min(values %$offsets)));
}

sub fix_movs {
	my $function = shift;
	my $fix = sub {
		my $instruction = shift;
		match ($instruction) {
			with (ASM_Mov $src $dst) {
				if ($src->{tag} eq 'ASM_Stack' && $dst->{tag} eq 'ASM_Stack') {
					return (::ASM_Mov($src, ::ASM_Reg(::R10())), ::ASM_Mov(::ASM_Reg(::R10()), $dst));
				} else {
					return $instruction;
				}
			} 
			default { return $instruction; }
		}	
	};
	my ($name, $instructions) = ::extract('ASM_Function', $function);
	$function->{values}[1] = [ map { $fix->($_) } @$instructions ];
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
		with (ASM_AllocateStack $bytes) {
			return "\tsubq \$$bytes, %rsp\n";
		}
		with (ASM_Neg) {
			return "\tnegl";
		}
		with (ASM_Not) {
			return "\tnotl";
		}
		with (ASM_Reg $reg) {
			if ($reg->{tag} eq 'AX') { return "%eax" }
			elsif ($reg->{tag} eq 'R10') {return "%r10d" }
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
