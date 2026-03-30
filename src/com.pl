#!/usr/bin/env perl
use strict;
use warnings;
use feature qw(say);

use File::Slurp;
use Data::Dumper;
use Cwd qw(abs_path);

our $src_dir;
BEGIN {
	push(@INC, $src_dir = abs_path(__FILE__) =~ s|[^/]+$||r);
}

use Utils qw(print_tree);
use Lexer;
use Parser;
use Semantics;
use TAC;
use CodeGen;
use Emitter;


our $global_counter = 0;
my $error_code = 255;

# ARGS
our %debug;
my @src_files;
my $target_phase = "";
my $dont_link = 0;

foreach (@ARGV) {
	if (/\.c$/) {
		push @src_files, $_;
	} elsif (/^--(lex|parse|validate|tac|tacky|codegen)$/) {
		$target_phase = $1;
	} elsif (/^-d(\w*)$/) {
		$debug{$_} = 1 for (split('', $1 ? $1 : "lpstceS"));
	} elsif (/^-c$/) {
		$dont_link = 1;
	}
}

my @asm_files;
for my $src_file (@src_files) {
	say ">>> COMPILING file: $src_file\n";
	say(read_file($src_file) . "\n");

	# PREPROCESS
	my $prep_file = $src_file =~ s/\.c$/.i/r;
	qx/gcc -E -P $src_file -o $prep_file/;

	# LEX
	$error_code = 1;
	my $src_str = read_file($prep_file);
	unlink($prep_file);
	my @tokens = Lexer::tokenize($src_str);
	say("> Lexer\n" . join("\n", @tokens) . "\n") if $debug{l};
	if ($target_phase eq 'lex') {
		$error_code = 0; exit;
	}

	# PARSE
	$error_code = 2;
	my $ast = Parser::parse(@tokens);
	if ($debug{p}) {
		say "> Parser";
		print_tree($ast);
	}
	if ($target_phase eq 'parse') {
		$error_code = 0; exit;
	}

	# SEMANTICS
	$error_code = 3;
	Semantics::run($ast);
	if ($debug{s}) {
		say "> Validator";
		print_tree($ast);
	}
	if ($debug{S}) {
		say "> Symbol table";
		say(Dumper(\%Semantics::symbol_table));
	}
	if ($target_phase eq 'validate') {
		$error_code = 0; exit;
	}

	# TAC
	$error_code = 4;
	my $tac = TAC::emit_TAC($ast);
	if ($debug{t}) {
		say "> TAC tree";
		print_tree($tac);
	}
	if ($target_phase =~ /^tac/) {
		$error_code = 0; exit;
	}

	# ASSEMBLY GEN
	$error_code = 5;
	my $asm = CodeGen::generate($tac);
	if ($debug{c}) {
		say "> ASM tree";
		print_tree($asm);
	}
	if ($debug{S}) {
		say "> ASM Symbol table";
		say(Dumper(\%CodeGen::asm_symbol_table));
	}
	if ($target_phase eq 'codegen') {
		$error_code = 0; exit;
	}

	# EMIT CODE
	$error_code = 6;
	my $asm_file = $src_file =~ s/\.c$/.s/r;
	my $code = Emitter::emit_code($asm);
	if ($debug{e}) {
		say "> Assembly";
		say($code);
	}
	write_file($asm_file, $code);
	push @asm_files, $asm_file;
	say "<<< DONE file: $src_file\n";
}

# ASSEMBLE
$error_code = 7;
if ($dont_link != 0) {
	qx(gcc -c $_ -o @{[ s/\.s$/.o/r ]}) for @asm_files;
}
else {
	qx(gcc @asm_files -o @{[ $asm_files[0] =~ s/\.s$//r ]});
}
unlink($_) for (@asm_files);
$error_code = 0;

END {
	$? = $error_code;
}


