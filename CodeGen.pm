package CodeGen;
use strict;
use warnings;
use feature qw(say);
use Types::Algebraic;


sub translate_to_ASM {
	my $node = shift;
	match ($node) {
		with (Program $declarations) {
			return ::AsmProgram([ map { translate_to_ASM($_) } @$declarations ]);
		}
		with (FunctionDeclaration $name $body) {
			return ::AsmFunction(
				$name,
			   	[ map { translate_to_ASM($_) } @$body ]
			);
		}
		with (Return $exp) {
			return (
				::Mov(translate_to_ASM($exp), ::Register()),
			   	::Ret()
			);
		}
		with (ConstantExp $val) {
			return ::Imm($val);
		}
	}
}

sub emit_code {
	my $node = shift;
	match ($node) {
		with (AsmProgram $declarations) {
			my $code = join "", map { emit_code($_) } @$declarations;
			$code .= '.section .note.GNU-stack,"",@progbits' . "\n"; 
			return $code;
		}
		with (AsmFunction $name $instructions) {
			my $code = "	.globl $name\n";
			$code .= "$name:\n";
			$code .= join "", map { "\t" . emit_code($_) } @$instructions;
			return $code;
		}
		with (Mov $src $dest) {
			return "movl " . emit_code($src) . ", " . emit_code($dest) . "\n";
		}
		with (Ret) {
			return "ret\n";
		}
		with (Imm $val) {
			return "\$$val";
		}
		with (Register) {
			return "%eax";
		}
		default {
			die "unknown asm node $node";
		}
	}
}



1;
