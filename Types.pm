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
	| Operator :op;

# AST
data _Program = 
	Program :Declarations;
data Declaration =
	VarDeclaration :name :OptExpression_initializer
	| FunDeclaration :name :Identifier_params :OptBlock_body;
data _Block = 
	Block :StatementOrDeclaration_blockItems;
data Statement = 
	Null
	| Return :Expression 
	| Expression :Expression
	| If :Expression_cond :Statement_then :OptStatement_else
	| Compound :Block
	| Break :label
	| Continue :label
	| While :Expression_cond :Statement_body :label
	| DoWhile :Statement_body :Expression_cond :label
	| For :VarDeclOrOptExpr_init :OptExpression_cond  :OptExpression_post :Statement_body :label;
data _Expression = 
	ConstantExp :value
	| Var :ident
	| Unary :UnaryOperator :Expression
	| Binary :BinaryOperator :Expression1 :Expression2
	| Assignment :LExpression :RExpression
	| Conditional :Expression_cond :Expression_then :Expression_else
	| FunctionCall :ident :Expression_args;
data UnaryOperator = Complement | Negate | Not;
data BinaryOperator = Add | Subtract | Multiply | Divide | Modulo | And | Or | Equal | NotEqual | LessThan | LessOrEqual | GreaterThan | GreaterOrEqual; 

# Types
data Type = 
	Int
	| FunType :param_count;

# TAC AST
data TAC_Program = 
	TAC_Program :Declarations;
data TAC_Declaration = 
	TAC_Function :identifier :params :Instructions;
data TAC_Instruction =
	TAC_Return :Value
	| TAC_Unary :UnaryOperator :Value_src :Value_dst
	| TAC_Binary :BinaryOperator :Value_1 :Value_2 :Value_dst
	| TAC_Copy :Value_src :Value_dst
	| TAC_Jump :target
	| TAC_JumpIfZero :Value_cond :target
	| TAC_JumpIfNotZero :Value_cond :target
	| TAC_Label :ident
	| TAC_FunCall :name :Value_params :Value_dst;
data TAC_Value =
	TAC_Constant :int
	| TAC_Variable :name;
data TAC_UnaryOperator = 
	TAC_Complement | TAC_Negate | TAC_Not;
data TAC_BinaryOperator = 
	TAC_Add | TAC_Subtract | TAC_Multiply | TAC_Divide | TAC_Modulo | TAC_And | TAC_Or | TAC_Equal | TAC_NotEqual | TAC_LessThan | TAC_LessOrEqual | TAC_GreaterThan | TAC_GreaterOrEqual;


# Assembly AST
data ASM_Program =
	ASM_Program :Declarations;
data ASM_Declaration =
	ASM_Function :name :Instructions;
data ASM_Instruction =
	ASM_Mov :Operand_src :Operand_dst
	| ASM_Unary :UnaryOperator :Operand
	| ASM_Binary :BinaryOperator :Operand1 :Operand2
	| ASM_Cmp :Operand1 :Operand2
	| ASM_Idiv :Operand
	| ASM_Cdq
	| ASM_Jmp :ident
	| ASM_JmpCC :Cond :ident
	| ASM_SetCC :Cond :Operand
	| ASM_Label :ident
	| ASM_AllocateStack :bytes
	| ASM_Ret;
data ASM_UnaryOperator = 
	ASM_Neg | ASM_Not;
data ASM_BinaryOperator = 
	ASM_Add | ASM_Sub | ASM_Mult;
data ASM_Operand = 
	ASM_Imm :int 
	| ASM_Reg :Reg
	| ASM_Pseudo :id
	| ASM_Stack :offset;
data AMS_CondCode = 
	E | NE | G | GE | L | LE;
data ASM_Register =
	AX | DX | R10 | R11;




### UTILS

sub is_one_of {
	my ($adt, @tags) = @_;
	return index_of_in($adt, @tags) != -1;
}

sub index_of_in {
	my ($adt, @tags) = @_;
	my $n = 0;
	for my $tag (@tags) {
		return $n if ($tag eq $adt->{tag});
		$n++;
	}
	return -1;
}

sub extract {
	my ($adt, @possible_tags) = @_;
	for my $tag (@possible_tags) {
		return $adt->{values}->@* if ($tag eq $adt->{tag});
	}
	return ();
}

sub extract_or_die {
	my ($adt, $expected_tag) = @_;
	die($adt->{tag} . " neni $expected_tag") unless $expected_tag eq $adt->{tag};
	return $adt->{values}->@*;
}

sub print_AST {
	my $tab = "  ";
	my $print_node = sub {
		my ($node, $indent) = @_;
		if ($node isa Types::Algebraic::ADT) {
			say(($tab x $indent) . $node->{tag});
			__SUB__->($_, $indent + 1) for $node->{values}->@*;
		} elsif (ref($node) eq 'ARRAY') {
			say(($tab x $indent) . 'array:');
			__SUB__->($_, $indent + 1) for $node->@*;
		} else {
			say(($tab x $indent) . ($node // 'undef'));
		}
	};
	$print_node->(shift(), 0);
	print "\n";
}

1;

