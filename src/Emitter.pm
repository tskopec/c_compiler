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
			if ($init->get('val') != 0 || $init_word eq 'double') {
				$code .= "\t.data\n";
				$code .= "\t.align $alignment\n";
				$code .= "$name:\n";
				$code .= "\t.$init_word " . sprintf("%a", $init->get('val')) . "\n";
			} else {
				$code .= "\t.bss\n";
				$code .= "\t.align $alignment\n";
				$code .= "$name:\n";
				$code .= "\t.zero $init_bytes\n";
			}
			return $code;
		},
		ASM_StaticConstant => sub($name, $alignment, $init) {
			my ($init_bytes, $init_word) = translate_type($init);
			my $code = ".section .rodata\n";
			$code .= "\t.align $alignment\n";
			$code .= "$name:\n";
			$code .= "\t.$init_word " . $init->get('val') . "\n";
			return $code;
		},
		ASM_Mov => sub($type, $src, $dst) {
			my ($n_bytes, $suffix) = translate_type($type);
			return "\tmov" . $suffix . " " . emit_code($src, $n_bytes) . ", " . emit_code($dst, $n_bytes) . "\n";
		},
		ASM_Movsx => sub($src, $dst) {
			return "\tmovslq " . emit_code($src) . ", " . emit_code($dst, 8) . "\n";
		},
		ASM_Ret => sub() {
			my $code = "\tmovq %rbp, %rsp\n";
			$code .= "\tpopq %rbp\n";
			$code .= "\tret\n";
			return $code;
		},
		ASM_Cvtsi2sd => sub($type, $src, $dst) {
			my ($n_bytes, $suffix) = translate_type($type);
			return "\tcvtsi2sd" . $suffix . emit_code($src) . ", " . emit_code($dst);
		},
		ASM_Cvttsd2si => sub($type, $src, $dst) {
			my ($n_bytes, $suffix) = translate_type($type);
			return "\tcvttsd2si" . $suffix . emit_code($src) . ", " . emit_code($dst);
		},
		ASM_Unary => sub($operator, $type, $operand) {
			my ($n_bytes, $suffix) = translate_type($type);
			return emit_code($operator) . $suffix . " " . emit_code($operand, $n_bytes) . "\n";
		},
		ASM_Binary => sub($operator, $type, $src, $dst) {
			my ($n_bytes, $suffix) = translate_type($type);
			return $operator->match({
				ASM_Xor => "\txorpd " . emit_code($src, 8) . ", " . emit_code($dst, 8) . "\n",
				ASM_Mult => "\tmulsd " . emit_code($src, 8) . ", " . emit_code($dst, 8) . "\n",
				default => emit_code($operator) . $suffix . " " . emit_code($src, $n_bytes) . ", " . emit_code($dst, $n_bytes) . "\n"
			});
		},
		"ASM_Idiv, ASM_Div" => sub($type, $operand) {
			my ($n_bytes, $suffix) = translate_type($type);
			return "\t" . lc(strip_prefix($node->{':tag'})) . $suffix . " " . emit_code($operand, $n_bytes) . "\n";
		},
		ASM_Cdq => sub($type) {
			return "\tcdq\n" if $type->is('ASM_Longword');
			return "\tcqo\n" if $type->is('ASM_Quadword');
			die 'unknown cdq type $type';
		},
		ASM_Cmp => sub($type, $first, $second) {
			my ($n_bytes, $suffix) = translate_type($type);
			if ($type->is('ASM_Double')) {
				return "\tcomisd " . emit_code($first, 8) . ", " . emit_code($second, 8) . "\n";
			} else {
				return "\tcmp" . $suffix . " " . emit_code($first, $n_bytes) . ", " . emit_code($second, $n_bytes) . "\n";
			}
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
		ASM_Neg => "\tneg",
		ASM_Not => "\tnot",
		ASM_Shr => "\tshr",
		ASM_DivDouble => "\tdiv",
		ASM_And => "\tand",
		ASM_Or => " \tor",
		ASM_Add => "\tadd",
		ASM_Sub => "\tsub",
		ASM_Mult => "\timul",
		ASM_Reg => sub($reg) {
			state $register_names = {
				ASM_AX => { 1 => "%al", 4 => "%eax", 8 => "%rax" },
				ASM_CX => { 1 => "%cl", 4 => "%ecx", 8 => "%rcx" },
				ASM_DX => { 1 => "%dl", 4 => "%edx", 8 => "%rdx" },
				ASM_DI => { 1 => "%dil", 4 => "%edi", 8 => "%rdi" },
				ASM_SI => { 1 => "%sil", 4 => "%esi", 8 => "%rsi" },
				ASM_R8 => { 1 => "%r8b", 4 => "%r8d", 8 => "%r8" },
				ASM_R9 => { 1 => "%r9b", 4 => "%r9d", 8 => "%r9" },
				ASM_R10 => { 1 => "%r10b", 4 => "%r10d", 8 => "%r10" },
				ASM_R11 => { 1 => "%r11b", 4 => "%r11d", 8 => "%r11" },
				ASM_SP => { 1 => "%rsp", 4 => "%rsp", 8 => "%rsp" },
				ASM_XMM0 => => { 8 => "%xmm0" },
				ASM_XMM1 => => { 8 => "%xmm1" },
				ASM_XMM2 => => { 8 => "%xmm2" },
				ASM_XMM3 => => { 8 => "%xmm3" },
				ASM_XMM4 => => { 8 => "%xmm4" },
				ASM_XMM5 => => { 8 => "%xmm5" },
				ASM_XMM6 => => { 8 => "%xmm6" },
				ASM_XMM7 => => { 8 => "%xmm7" },
				ASM_XMM14 => => { 8 => "%xmm14" },
				ASM_XMM15 => => { 8 => "%xmm15" },
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
	return $type->match({
		ASM_Longword => (4, 'l'),
		ASM_Quadword => (8, 'q'),
		ASM_Double => (8, 'sd'),
		'T_Int, I_IntInit, I_UIntInit' => (4, 'long'),
		'T_Long, I_LongInit, I_ULongInit' => (8, 'quad'),
		T_DoubleInit => (8, 'double'),
		default => sub() {
			die "unknown type $type";
		}
	});
}

sub strip_prefix {
	return shift() =~ s/^[A-Z]*_//r;
}

1;


