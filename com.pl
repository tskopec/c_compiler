#!/usr/bin/env perl
use strict;
use warnings;
use feature qw(say);
use File::Slurp;

use lib ".";
use Types;
use Lexer;
use Parser;
use TAC;
use CodeGen;


# ARGS
my $src_path;
my $target_phase = '';
my $debug = 0;
foreach (@ARGV) {
	if (/\.c$/) {
		$src_path = $_;
	} elsif (/^--(lex|parse|tac|codegen)$/) {
		$target_phase = $1;
	} elsif (/^-d$/) {
		$debug = 1;
	}
}

# PREPROCESS
my $prep_file = $src_path =~ s/c$/i/r;
qx/gcc -E -P $src_path -o $prep_file/;

# LEX
my $src_str = read_file($prep_file);
my @tokens = Lexer::tokenize($src_str);
say(join("\n", @tokens) . "\n") if $debug;
exit 0 if ($target_phase eq 'lex'); 	

# PARSE
my $ast = Parser::parse(@tokens);
print_AST($ast) if $debug;
exit 0 if ($target_phase eq 'parse');

# TAC
my $tac = TAC::emit_TAC($ast);
print_AST($tac) if $debug;
exit 0 if ($target_phase eq 'tac');

# ASSEMBLY GEN
my $asm = CodeGen::translate_to_ASM($tac);
print_AST($asm) if $debug;
exit 0 if ($target_phase eq 'codegen');

# EMIT CODE
my $asm_file = $src_path =~ s/c$/s/r;
my $code = CodeGen::emit_code($asm);
write_file($asm_file, $code);

# ASSEMBLE
my $bin_file = $src_path =~ s/\.c$//r;
qx/gcc $asm_file -o $bin_file/;

# CLEANUP
END {
	no warnings "uninitialized";
	unlink($prep_file, $asm_file); 
	say "compiler done";
}
