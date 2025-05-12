#!/usr/bin/env perl
use strict;
use warnings;
use feature qw(say);
use File::Slurp;

require "./Lexer.pm";
require "./Parser.pm";
require "./CodeGen.pm";
require "./Types.pm";

# ARGS
my $src_path;
my $target_phase = '';
foreach (@ARGV) {
	if (/\.c$/) {
		$src_path = $_;
	} elsif (/^--(lex|parse|codegen)$/) {
		$target_phase = $1;
	} 
}

# PREPROCESS
my $prep_file = $src_path =~ s/c$/i/r;
qx/gcc -E -P $src_path -o $prep_file/;

# LEX
my $src_str = read_file($prep_file);
my @tokens = tokenize($src_str);
if ($target_phase eq 'lex') {
	#say $_ for (@tokens);
	exit 0;
}	
# PARSE
my $ast = parse(@tokens);
if ($target_phase eq 'parse') {
	#print_AST($ast);
	exit 0;
}
# ASSEMBLY GEN
my $asm = translate_to_ASM($ast);
if ($target_phase eq 'codegen') {
	#print_AST($asm);
	exit 0;
}
# EMIT CODE
my $asm_file = $src_path =~ s/c$/s/r;
my $code = emit_code($asm);
write_file($asm_file, $code);

# ASSEMBLE
my $bin_file = $src_path =~ s/\.c$//r;
qx/gcc $asm_file -o $bin_file/;

# CLEANUP
qx/rm $prep_file $asm_file/;

say "compiler done";

