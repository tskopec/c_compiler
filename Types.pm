use strict;
use warnings;
use feature qw(say isa state);
use Types::Algebraic;

# Tokens
data Token = 
	Identifier :name
	| Constant :val
	| Keyword :word
	| Symbol :char;


# AST
data Program = 
	Program :Declarations;
data Declaration = 
	FunctionDeclaration :name :Statement_body
	| VariableDeclaration :name;
data Statement = 
	Return :Expression 
	| If :Expression_cond :Statement_then :Statement_else;
data Expression = 
	ConstantExp :value;


# Assembly AST
data AsmProgram =
	AsmProgram :Declarations;
data AsmDeclaration =
	AsmFunction :name :Instructions;
data Instruction =
	Mov :Operand_src :Operand_dst
	| Ret;
data Operand = 
	Imm :int 
	| Register;





sub print_AST {
	state $tab = "    ";
	my ($node, $indent) = @_;
	if ($node isa Types::Algebraic::ADT) {
		say(($tab x $indent) . $node->{tag});
		for my $val ($node->{values}->@*) {
			print_AST($val, $indent + 1);
		}
	} elsif (ref($node) eq 'ARRAY') {
		for my $val ($node->@*) {
			print_AST($val, $indent);
		}
	} elsif (ref($node) eq 'HASH') {
		die "todo print hash";
	} else {
		say(($tab x $indent) . $node);
	}
}
1;

