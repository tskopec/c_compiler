#!/usr/bin/env perl
use strict;
use warnings;
use feature qw(say);
use File::Slurp;

use lib ".";
use Types;
use Lexer;
use Parser;
use SemanticAnalysis;
use TAC;
use CodeGen;
use Emitter;

our $global_counter = 0;

# ARGS
my @src_paths;
my $target_phase = '';
my $debug = 0;
foreach (@ARGV) {
	if (/\.c$/) {
		push @src_paths, $_;
	} elsif (/^--(lex|parse|validate|tac|codegen)$/) {
		$target_phase = $1;
	} elsif (/^-d$/) {
		$debug = 1;
	}
}

for my $src_path (@src_paths) {
	eval { compile($src_path) };
	if ($@) {
		print "ERROR in src file: ${src_path}:\n$@";
		say "------------------------------------------";
	}
} continue {
	$global_counter = 0;
}
 

END {
	say "compiler done";
}

sub compile {
	my $src_path = shift;
	# PREPROCESS
	my $prep_file = $src_path =~ s/c$/i/r;
	qx/gcc -E -P $src_path -o $prep_file/;

	# LEX
	my $src_str = read_file($prep_file);
	say "COMPILING $src_path:\n $src_str\n" if $debug;
	unlink($prep_file); 
	my @tokens = Lexer::tokenize($src_str);
	say(join("\n", @tokens) . "\n") if $debug;
	next if ($target_phase eq 'lex'); 	

	# PARSE
	my $ast = Parser::parse(@tokens);
	print_AST($ast) if $debug;
	next if ($target_phase eq 'parse');

	# SEMANTICS
	SemanticAnalysis::run($ast);
	print_AST($ast) if $debug;
	next if ($target_phase eq 'validate');

	# TAC
	my $tac = TAC::emit_TAC($ast);
	print_AST($tac) if $debug;
	next if ($target_phase eq 'tac');

	# ASSEMBLY GEN
	my $asm = CodeGen::translate_to_ASM($tac);
	CodeGen::fix_up($asm);
	print_AST($asm) if $debug;
	next if ($target_phase eq 'codegen');

	# EMIT CODE
	my $asm_file = $src_path =~ s/c$/s/r;
	my $code = Emitter::emit_code($asm);
	write_file($asm_file, $code);
	 
	# ASSEMBLE
	my $bin_file = $src_path =~ s/\.c$//r;
	qx/gcc $asm_file -o $bin_file/;
	unlink($asm_file); 
}


