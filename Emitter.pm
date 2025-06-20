package CodeGen;
use strict;
use warnings;
use feature qw(say);
use Types::Algebraic;


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


