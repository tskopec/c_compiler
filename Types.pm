# zda se ze Types::Algebraic nefachci kdyz by tohle bylo ve vlastnim packagi, takze je to v main a z jinych packagu se typy volaji s prefixem :: 
# (ale ne v match with(...) ..)
# TODO vymyslet nejak jinak?

use strict;
use warnings;
use feature qw(say isa current_sub);
use Types::Algebraic;

# Tokens
data Token = 
	Identifier :name
	| Constant :val
	| Keyword :word
	| Symbol :char
	| UnOp :op;


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
	ConstantExp :value
	| Unary :UnaryOperator :Expression;
data UnaryOperator = 
	Complement
	| Negate;


# TAC AST
data TAC_Program = 
	TAC_Program :Declarations;
data TAC_Declaration = 
	TAC_Function :identifier :Instructions;
data TAC_Instruction =
	TAC_Return :Value
	| TAC_Unary :UnaryOperator :Value_src :Value_dst;
data TAC_Value =
	TAC_Constant :int
	| TAC_Variable :name;
data TAC_UnaryOperator = 
	TAC_Complement
	| TAC_Negate;


# Assembly AST
data ASM_Program =
	ASM_Program :Declarations;
data ASM_Declaration =
	ASM_Function :name :Instructions;
data ASM_Instruction =
	ASM_Mov :Operand_src :Operand_dst
	| ASM_Unary :UnaryOperator :Operand
	| ASM_AllocateStack :bytes
	| ASM_Ret;
data ASM_UnaryOperator = 
	ASM_Neg
	| ASM_Not;
data ASM_Operand = 
	ASM_Imm :int 
	| ASM_Reg :Reg
	| ASM_Pseudo :id
	| ASM_Stack :offset;
data ASM_Register =
	AX
	| R10;





sub print_AST {
	my $tab = "    ";
	my $print_node = sub {
		my ($node, $indent) = @_;
		if ($node isa Types::Algebraic::ADT) {
			say(($tab x $indent) . $node->{tag});
			for my $val ($node->{values}->@*) {
				__SUB__->($val, $indent + 1);
			}
		} elsif (ref($node) eq 'ARRAY') {
			say(($tab x $indent) . 'array:');
			for my $val ($node->@*) {
				__SUB__->($val, $indent + 1);
			}
		} else {
			say(($tab x $indent) . $node);
		}
	};
	$print_node->(+shift, 0);
	print "\n";
}
1;

