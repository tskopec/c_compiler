package Emitter;
use strict;
use warnings;
use feature qw(say);
use Types::Algebraic;


sub emit_code {
	my ($node, $parent) = @_;
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
		with (ASM_Cmp $a $b) {
			return "\tcmpl " . emit_code($a) . ", " . emit_code($b) . "\n";
		}
		with (ASM_Jmp $label) {
			return "\tjmp .L$label\n";
		}
		with (ASM_JmpCC $cond $label) {
			return "\tj" . lc($cond->{tag}) . " .L$label\n";
		}
		with (ASM_SetCC $cond $operand) {
			return "\tset" . lc($cond->{tag}) . " " . emit_code($operand, $node) . "\n";
		}
		with (ASM_Label $ident) {
			return ".L$ident:\n";
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
			my $one_byte = $parent->{tag} eq 'ASM_SetCC';
			if	  ($reg->{tag} eq 'AX')	 { return $one_byte ? "%al"   : "%eax"; }
			elsif ($reg->{tag} eq 'DX')  { return $one_byte ? "%dl"   : "%edx"; }
			elsif ($reg->{tag} eq 'R10') { return $one_byte ? "%r10b" : "%r10d"; }
			elsif ($reg->{tag} eq 'R11') { return $one_byte ? "%r11b" : "%r11d"; }
			else { die "unknown register $reg"; }
		}
		with (ASM_Stack $offset) {
			return "$offset(%rbp)";
		}
		with (ASM_Imm $val) {
			return "\$$val";
		}
		default { die "unknown asm node $node"; }
	}
}



1;


