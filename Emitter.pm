package Emitter;
use strict;
use warnings;
use feature qw(say state);
use Types::Algebraic;


sub emit_code {
	my $node = shift;
	my $register_width = shift // 4;
	match ($node) {
		with (ASM_Program $definitions) {
			my $code = join "\n", map { emit_code($_) } @$definitions;
			$code .= '.section .note.GNU-stack,"",@progbits' . "\n"; 
			return $code;
		}
		with (ASM_Function $name $global $instructions) {
			my $code = $global ? "\t.global $name\n" : "";
			$code .= "\t.text\n";
			$code .= "$name:\n";
			$code .= "\tpushq %rbp\n";
			$code .= "\tmovq %rsp, %rbp\n";
			$code .= join "", map { emit_code($_) } @$instructions;
			return $code;
		} 
		with (ASM_StaticVariable $name $global $alignment $init) {
			my $code = $global ? "\t.global $name\n" : "";
			my ($init_bytes, $init_word) = translate_type($init);
			if ($init == 0) {
				$code .= "\t.bss\n";
				$code .= "\t.align $alignment\n";
				$code .= "$name:\n";
				$code .= "\t.zero $init_bytes\n";	
			} else {
				$code .= "\t.data\n";
				$code .= "\t.align $alignment\n";
				$code .= "$name:\n";
				$code .= "\t.$init_word $init\n";	
			}
			return $code;
		}
		with (ASM_Mov $type $src $dst) {
			my ($n_bytes, $suffix) = translate_type($type);
			return "\tmov" . $suffix . " " . emit_code($src, $n_bytes) . ", " . emit_code($dst, $n_bytes) . "\n";
		}
		with (ASM_Movsx $src $dst) {
			return "\tmovslq " . emit_code($src) . ", " . emit_code($dst);
		}
		with (ASM_Ret) {
			my $code = "\tmovq %rbp, %rsp\n";
			$code .=   "\tpopq %rbp\n";
			$code .=   "\tret\n";
			return $code;
		}
		with (ASM_Unary $operator $type $operand) {
			my ($n_bytes, $suffix) = translate_type($type);
			return emit_code($operator) . $suffix . " " . emit_code($operand, $n_bytes) . "\n";
		}
		with (ASM_Binary $operator $type $src $dst) {
			my ($n_bytes, $suffix) = translate_type($type);
			return emit_code($operator) . $suffix . " " . emit_code($src, $n_bytes) . ", " . emit_code($dst, $n_bytes) . "\n";
		}
		with (ASM_Idiv $type $operand) {
			my ($n_bytes, $suffix) = translate_type($type);
			return "\tidiv" . $suffix . " " . emit_code($operand, $n_bytes) . "\n";
		}
		with (ASM_Cdq $type) {
			return "\tcdq\n" if $type->{tag} eq 'ASM_Quadword';
			return "\tcqo\n" if $type->{tag} eq 'ASM_Longword';
			die 'unknown cdq type $type';
		}
		with (ASM_Cmp $type $a $b) {
			my ($n_bytes, $suffix) = translate_type($type);
			return "\tcmp" . $suffix . " " . emit_code($a, $n_bytes) . ", " . emit_code($b, $n_bytes) . "\n";
		}
		with (ASM_Jmp $label) {
			return "\tjmp .L$label\n";
		}
		with (ASM_JmpCC $cond $label) {
			return "\tj" . lc($cond->{tag}) . " .L$label\n";
		}
		with (ASM_SetCC $cond $operand) {
			return "\tset" . lc($cond->{tag}) . " " . emit_code($operand, 1) . "\n";
		}
		with (ASM_Label $ident) {
			return ".L$ident:\n";
		}
		with (ASM_Neg) {
			return "\tneg";
		}
		with (ASM_Not) {
			return "\tnot";
		}
		with (ASM_Add) {
			return "\tadd";
		}
		with (ASM_Sub) {
			return "\tsub";
		}
		with (ASM_Mult) {
			return "\timul";
		}
		with (ASM_Reg $reg) {
			state $register_names = {
				AX =>  { 1 => "%al",   4 => "%eax",  8 => "%rax" },
				CX =>  { 1 => "%cl",   4 => "%ecx",  8 => "%rcx" },
				DX =>  { 1 => "%dl",   4 => "%edx",  8 => "%rdx" },
				DI =>  { 1 => "%dil",  4 => "%edi",  8 => "%rdi" },
				SI =>  { 1 => "%sil",  4 => "%esi",  8 => "%rsi" },
				R8 =>  { 1 => "%r8b",  4 => "%r8d",  8 => "%r8"  },
				R9 =>  { 1 => "%r9b",  4 => "%r9d",  8 => "%r9"  },
				R10 => { 1 => "%r10b", 4 => "%r10d", 8 => "%r10" },
				R11 => { 1 => "%r11b", 4 => "%r11d", 8 => "%r11" },
				SP =>  { 1 => "%rsp",  4 => "%rsp",  8 => "%rsp" },
			};
			return $register_names->{$reg->{tag}}->{$register_width} // die "unknown register $reg w: $register_width";
		}
		with (ASM_Stack $offset) {
			return "$offset(%rbp)";
		}
		with (ASM_Data $ident) {
			return "$ident(%rip)";
		}
		with (ASM_Imm $val) {
			return "\$$val";
		}
		with (ASM_Push $op) {
			return "\tpushq " . emit_code($op, 8) . "\n";
		}
		with (ASM_Call $label) {
			return "\tcall $label" . (Semantics::get_symbol_attr($label, 'defined') ? "" : '@PLT') . "\n";
		}
		default { die "unknown asm node $node"; }
	}
}

sub translate_type {
	my $type = shift;
	return (4, 'l') if $type->{tag} eq 'ASM_Longword';
	return (8, 'q') if $type->{tag} eq 'ASM_Quadword';
	return (4, 'long') if $type->{tag} eq 'IntType';
	return (8, 'quad') if $type->{tag} eq 'LongType';
	die "unknown type $type (translate_type)";
}



1;


