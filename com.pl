#!/usr/bin/env perl
use strict;
use warnings;
use feature qw(say);
use File::Slurp;

use lib ".";

use ADT::AlgebraicTypes qw(print_tree);
use Lexer;
use Parser;
#use Semantics;
#use TAC;
#use CodeGen;
#use Emitter;


our $global_counter = 0;

# ARGS
our $debug = 0;
my @src_files;
my $target_phase = "";
my $dont_link = 0;


foreach (@ARGV) {
	if (/\.c$/) {
		push @src_files, $_;
	} elsif (/^--(lex|parse|validate|tac|codegen)$/) {
		$target_phase = $1;
	} elsif (/^-d$/) {
		$debug = 1;
	} elsif (/^-c$/) {
		$dont_link = 1;
	}
}

for my $src_file (@src_files) {
	eval { compile($src_file) };
	if ($@) {
		print "ERROR in src file: $src_file:\n$@";
	} else {
		say "OK, src file: $src_file";
	}
	say "------------------------------------------";
} continue {
	$global_counter = 0;
}
 

END {
	say "compiler done";
}

sub compile {
	my $src_file = shift;
	# PREPROCESS
	my $prep_file = $src_file =~ s/c$/i/r;
	qx/gcc -E -P $src_file -o $prep_file/;

	# LEX
	my $src_str = read_file($prep_file);
	say "COMPILING $src_file:\n $src_str\n" if $debug;
	unlink($prep_file); 
	my @tokens = Lexer::tokenize($src_str);
	say(join("\n", @tokens) . "\n") if $debug;
	return if ($target_phase eq 'lex'); 	

	# PARSE
	my $ast = Parser::parse(@tokens);
	print_tree($ast) if $debug;
	return if ($target_phase eq 'parse');
	#
	#	# SEMANTICS
	#	Semantics::run($ast);
	#	print_AST($ast) if $debug;
	#	return if ($target_phase eq 'validate');
	#
	#	# TAC
	#	my $tac = TAC::emit_TAC($ast);
	#	print_AST($tac) if $debug;
	#	return if ($target_phase eq 'tac');
	#
	#	# ASSEMBLY GEN
	#	my $asm = CodeGen::generate($tac);
	#	print_AST($asm) if $debug;
	#	return if ($target_phase eq 'codegen');
	#
	#	# EMIT CODE
	#	my $asm_file = $src_file =~ s/c$/s/r;
	#	my $code = Emitter::emit_code($asm);
	#	say($code) if $debug;
	#	write_file($asm_file, $code);
	#	 
	#	# ASSEMBLE
	#	if ($dont_link) {
	#		my $obj_file = $src_file =~ s/\.c$/.o/r;
	#		qx/gcc -c $asm_file -o $obj_file/;
	#	} else {
	#		my $bin_file = $src_file =~ s/\.c$//r;
	#		qx/gcc $asm_file -o $bin_file/;
	#	}
	#	unlink($asm_file); 
}



