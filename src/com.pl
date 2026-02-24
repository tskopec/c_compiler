#!/usr/bin/env perl
use strict;
use warnings;
use feature qw(say);
use File::Slurp;

use lib "."; # proc to nefachci v idei?

use ADT::AlgebraicTypes qw(print_tree);
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
my $src_file;
my $target_phase = "";
my $dont_link = 0;

foreach (@ARGV) {
	if (/\.c$/) {
		$src_file = $_;
	} elsif (/^--(lex|parse|validate|tac|codegen)$/) {
		$target_phase = $1;
	} elsif (/^-d(\w*)$/) {
		$debug{$_} = 1 for (split('', $1 ? $1 : "lpstce"));
	} elsif (/^-c$/) {
		$dont_link = 1;
	}
}

# PREPROCESS
my $prep_file = $src_file =~ s/c$/i/r;
qx/gcc -E -P $src_file -o $prep_file/;

# LEX
$error_code = 1;
my $src_str = read_file($prep_file);
say "COMPILING $src_file:\n $src_str\n" if (grep { $_ } (values %debug));
unlink($prep_file);
my @tokens = Lexer::tokenize($src_str);
say(join("\n", @tokens) . "\n") if $debug{l};
exit if ($target_phase eq 'lex');

# PARSE
$error_code = 2;
my $ast = Parser::parse(@tokens);
print_tree($ast) if $debug{p};
exit if ($target_phase eq 'parse');

# SEMANTICS
$error_code = 3;
Semantics::run($ast);
print_tree($ast) if $debug{s};
exit if ($target_phase eq 'validate');

# TAC
$error_code = 4;
my $tac = TAC::emit_TAC($ast);
print_tree($tac) if $debug{t};
exit if ($target_phase eq 'tac');

# ASSEMBLY GEN
$error_code = 5;
my $asm = CodeGen::generate($tac);
print_tree($asm) if $debug{c};
exit if ($target_phase eq 'codegen');

# EMIT CODE
$error_code = 6;
my $asm_file = $src_file =~ s/c$/s/r;
my $code = Emitter::emit_code($asm);
say($code) if $debug{e};
write_file($asm_file, $code);

# ASSEMBLE
$error_code = 7;
if ($dont_link) {
	my $obj_file = $src_file =~ s/\.c$/.o/r;
	qx/gcc -c $asm_file -o $obj_file/;
} else {
	my $bin_file = $src_file =~ s/\.c$//r;
	qx/gcc $asm_file -o $bin_file/;
}
unlink($asm_file);

$error_code = 0;

END {
	$? = $error_code;
}


