package CodeGen;
use strict;
use warnings;
use feature qw(say);
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

sub emit_code {
	#	my $node = shift;
	#	match ($node) {
	#		with (AsmProgram $declarations) {
	#			my $code = join "", map { emit_code($_) } @$declarations;
	#			$code .= '.section .note.GNU-stack,"",@progbits' . "\n"; 
	#			return $code;
	#		}
	#		with (AsmFunction $name $instructions) {
	#			my $code = "	.globl $name\n";
	#			$code .= "$name:\n";
	#			$code .= join "", map { "\t" . emit_code($_) } @$instructions;
	#			return $code;
	#		}
	#		with (AsmMove $src $dest) {
	#			return "movl " . emit_code($src) . ", " . emit_code($dest) . "\n";
	#		}
	#		with (AsmReturn) {
	#			return "ret\n";
	#		}
	#		with (AsmImm $val) {
	#			return "\$$val";
	#		}
	#		with (Register) {
	#			return "%eax";
	#		}
	#		default {
	#			die "unknown asm node $node";
	#		}
	#	}
}



1;
