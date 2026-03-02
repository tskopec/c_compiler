package Emitter;
use strict;
use warnings;
use feature qw(say state signatures);

use ADT::AlgebraicTypes qw(:ASM);


sub emit_code {
	my $node = shift;
	my $register_width = shift // 4;
	return $node->match({
		ASM_Program => sub($definitions) {
			my $code = join "\n", map { emit_code($_) } @$definitions;
			$code .= '.section .note.GNU-stack,"",@progbits' . "\n"; 
			return $code;
		},
		ASM_Function => sub($name, $global, $instructions) {
			my $code = $global ? "\t.globl $name\n" : "";
			$code .= "\t.text\n";
			$code .= "$name:\n";
			$code .= "\tpushq %rbp\n";
			$code .= "\tmovq %rsp, %rbp\n";
			$code .= join "", map { emit_code($_) } @$instructions;
			return $code;
		}, 
		ASM_StaticVariable => sub($name, $global, $alignment, $init) {
			my $code = $global ? "\t.globl $name\n" : "";
			my ($init_bytes, $init_word) = translate_type($init);
			if ($init->get('val') != 0) {
				$code .= "\t.data\n";
				$code .= "\t.align $alignment\n";
				$code .= "$name:\n";
				$code .= "\t.$init_word " . $init->get('val') . "\n";
			} else {
				$code .= "\t.bss\n";
				$code .= "\t.align $alignment\n";
				$code .= "$name:\n";
				$code .= "\t.zero $init_bytes\n";
			}
			return $code;
		},
		ASM_Mov => sub($type, $src, $dst) {
			my ($n_bytes, $suffix) = translate_type($type);
			return "\tmov" . $suffix . " " . emit_code($src, $n_bytes) . ", " . emit_code($dst, $n_bytes) . "\n";
		},
		ASM_Movsx => sub($src, $dst) {
			return "\tmovslq " . emit_code($src) . ", " . emit_code($dst);
		},
		ASM_Ret => sub() {
			my $code = "\tmovq %rbp, %rsp\n";
			$code .=   "\tpopq %rbp\n";
			$code .=   "\tret\n";
			return $code;
		},
		ASM_Unary => sub($operator, $type, $operand) {
			my ($n_bytes, $suffix) = translate_type($type);
			return emit_code($operator) . $suffix . " " . emit_code($operand, $n_bytes) . "\n";
		},
		ASM_Binary => sub($operator, $type, $src, $dst) {
			my ($n_bytes, $suffix) = translate_type($type);
			return emit_code($operator) . $suffix . " " . emit_code($src, $n_bytes) . ", " . emit_code($dst, $n_bytes) . "\n";
		},
		ASM_Idiv => sub($type, $operand) {
			my ($n_bytes, $suffix) = translate_type($type);
			return "\tidiv" . $suffix . " " . emit_code($operand, $n_bytes) . "\n";
		},
		ASM_Cdq => sub($type) {
			return "\tcdq\n" if $type->is('ASM_Longword');
			return "\tcqo\n" if $type->is('ASM_Quadword');
			die 'unknown cdq type $type';
		},
		ASM_Cmp => sub($type, $a, $b) {
			my ($n_bytes, $suffix) = translate_type($type);
			return "\tcmp" . $suffix . " " . emit_code($a, $n_bytes) . ", " . emit_code($b, $n_bytes) . "\n";
		},
		ASM_Jmp => sub($label) {
			return "\tjmp .L$label\n";
		},
		ASM_JmpCC => sub($cond, $label) {
			return "\tj" . lc(strip_prefix($cond->{':tag'})) . " .L$label\n";
		},
		ASM_SetCC => sub($cond, $operand) {
			return "\tset" . lc(strip_prefix($cond->{':tag'})) . " " . emit_code($operand, 1) . "\n";
		},
		ASM_Label => sub($ident) {
			return ".L$ident:\n";
		},
		ASM_Neg => sub() {
			return "\tneg";
		},
		ASM_Not => sub() {
			return "\tnot";
		},
		ASM_Add => sub() {
			return "\tadd";
		},
		ASM_Sub => sub() {
			return "\tsub";
		},
		ASM_Mult=> sub() {
			return "\timul";
		},
		ASM_Reg => sub($reg) {
			state $register_names = {
				ASM_AX =>  { 1 => "%al",   4 => "%eax",  8 => "%rax" },
				ASM_CX =>  { 1 => "%cl",   4 => "%ecx",  8 => "%rcx" },
				ASM_DX =>  { 1 => "%dl",   4 => "%edx",  8 => "%rdx" },
				ASM_DI =>  { 1 => "%dil",  4 => "%edi",  8 => "%rdi" },
				ASM_SI =>  { 1 => "%sil",  4 => "%esi",  8 => "%rsi" },
				ASM_R8 =>  { 1 => "%r8b",  4 => "%r8d",  8 => "%r8"  },
				ASM_R9 =>  { 1 => "%r9b",  4 => "%r9d",  8 => "%r9"  },
				ASM_R10 => { 1 => "%r10b", 4 => "%r10d", 8 => "%r10" },
				ASM_R11 => { 1 => "%r11b", 4 => "%r11d", 8 => "%r11" },
				ASM_SP =>  { 1 => "%rsp",  4 => "%rsp",  8 => "%rsp" },
			};
			return $register_names->{$reg->{':tag'}}->{$register_width} // die "unknown register $reg w: $register_width";
		},
		ASM_Stack => sub($offset) {
			return "$offset(%rbp)";
		},
		ASM_Data => sub($ident) {
			return "$ident(%rip)";
		},
		ASM_Imm => sub($val) {
			return "\$$val";
		},
		ASM_Push => sub($op) {
			return "\tpushq " . emit_code($op, 8) . "\n";
		},
		ASM_Call => sub($label) {
			return "\tcall $label" . (Semantics::get_symbol_attr($label, 'defined') ? "" : '@PLT') . "\n";
		},
		default => sub { die "unknown asm node $node"; }
	});
}

sub translate_type {
	my $type = shift;
	return (4, 'l') if $type->is('ASM_Longword');
	return (8, 'q') if $type->is('ASM_Quadword');
	return (4, 'long') if $type->is('T_IntType', 'I_IntInit');
	return (8, 'quad') if $type->is('T_LongType', 'I_LongInit');
	die "unknown type $type";
}

sub strip_prefix {
	return shift() =~ s/^[A-Z]*_//r;
}



1;


