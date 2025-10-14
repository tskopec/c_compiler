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
	| IntConstant :val
	| LongConstant :val
	| Keyword :word
	| Symbol :char
	| Operator :op;

# AST
data _Program = 
	Program :Declarations;
data Declaration =
	VarDeclaration :name :OptExpression_initializer :Type :OptStorageClass
	| FunDeclaration :name :VarDecl_params :OptBlock_body :Type :OptStorageClass;
data StorageClass =
	Static | Extern;
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
data _Expression = # Semantics::[gs]et_type count on :Type being the last param of expression
	ConstantExpr :Constant 
	| Var :ident # type in symtable
	| Cast :Expression :Type_target
	| Unary :UnaryOperator :Expression :Type
	| Binary :BinaryOperator :Expression1 :Expression2 :Type
	| Assignment :LExpression :RExpression :Type
	| Conditional :Expression_cond :Expression_then :Expression_else :Type
	| FunctionCall :ident :Expression_args :Type;
data UnaryOperator = 
	Complement | Negate | Not;
data BinaryOperator=  
	Add | Subtract | Multiply | Divide | Modulo | And | Or | Equal | NotEqual | LessThan | LessOrEqual | GreaterThan | GreaterOrEqual; 
data Constant = ConstInt :int | ConstLong :int;


# Types
data Type = 
	Int
	| Long
	| FunType :Type_params :Type_ret;
data IdentifierAttrs = 
	FunAttrs :defined :global
	| StaticAttrs :InitVal :global
	| LocalAttrs;
data InitialValue =
	Tentative | Initial :StaticInit | NoInitializer;
data StaticInit = IntInit :int | LongInit :int;


# TAC
data _TAC_Program = 
	TAC_Program :TopLvlDeclarations;
data TAC_TopLevelDeclaration = 
	TAC_StaticVariable :identifier :global :Type :StaticInit
	| TAC_Function :identifier :global :params :Instructions;
data TAC_Instruction =
	TAC_Return :Value
	| TAC_SignExtend :Value_src :Value_dst
	| TAC_Truncate :Value_src :Value_dst
	| TAC_Unary :UnaryOperator :Value_src :Value_dst
	| TAC_Binary :BinaryOperator :Value_1 :Value_2 :Value_dst
	| TAC_Copy :Value_src :Value_dst
	| TAC_Jump :target
	| TAC_JumpIfZero :Value_cond :target
	| TAC_JumpIfNotZero :Value_cond :target
	| TAC_Label :ident
	| TAC_FunCall :name :Value_params :Value_dst;
data TAC_Value =
	TAC_Constant :Constant
	| TAC_Variable :name;
data TAC_UnaryOperator = 
	TAC_Complement | TAC_Negate | TAC_Not;
data TAC_BinaryOperator = 
	TAC_Add | TAC_Subtract | TAC_Multiply | TAC_Divide | TAC_Modulo | TAC_And | TAC_Or | TAC_Equal | TAC_NotEqual | TAC_LessThan | TAC_LessOrEqual | TAC_GreaterThan | TAC_GreaterOrEqual;


# Assembly
data ASM_Program =
	ASM_Program :TopLvlDeclarations;
data ASM_Type = Longword | Quadword;
data ASM_TopLevelDeclaration =
	ASM_StaticVariable :name :global :int_alignment :StaticInit
	| ASM_Function :name :global :Instructions;
data ASM_Instruction =
	ASM_Mov :Type :Operand_src :Operand_dst
	| AMS_Movsx :Operand_src :Operand_dst
	| ASM_Unary :UnaryOperator :Type :Operand
	| ASM_Binary :BinaryOperator :Type :Operand1 :Operand2
	| ASM_Cmp :Type :Operand1 :Operand2
	| ASM_Idiv :Type :Operand
	| ASM_Cdq :Type
	| ASM_Jmp :ident
	| ASM_JmpCC :Cond :ident
	| ASM_SetCC :Cond :Operand
	| ASM_Label :ident
	| ASM_AllocateStack :bytes
	| ASM_DeallocateStack :bytes
	| ASM_Push :Operand
	| ASM_Call :ident
	| ASM_Ret;
data ASM_UnaryOperator = 
	ASM_Neg | ASM_Not;
data ASM_BinaryOperator = 
	ASM_Add | ASM_Sub | ASM_Mult;
data ASM_Operand = 
	ASM_Imm :int 
	| ASM_Reg :Reg
	| ASM_Pseudo :id
	| ASM_Stack :offset
	| ASM_Data :ident;
data ASM_CondCode = 
	E | NE | G | GE | L | LE;
data ASM_Register =
	AX | CX | DX | DI | SI | R8 | R9 | R10 | R11 | SP;




### UTILS

sub is_one_of {
	my ($adt, @tags) = @_;
	return index_of_in($adt, @tags) != -1;
}

sub index_of_in {
	my ($adt, @tags) = @_;
	unless ($adt isa Types::Algebraic::ADT) {
		say "warning (index_of_in): $adt not ADT" if ($::debug);
		return -1;
	}
	if (defined $adt) {
		my $n = 0;
		for my $tag (@tags) {
			return $n if ($tag eq $adt->{tag});
			$n++;
		}
	}
	return -1;
}

sub extract {
	my ($adt, @possible_tags) = @_;
	unless ($adt isa Types::Algebraic::ADT) {
		say "warning (extract): $adt not ADT" if ($::debug);
		return ();
	}
	for my $tag (@possible_tags) {
		return $adt->{values}->@* if ($tag eq $adt->{tag});
	}
	return ();
}

sub extract_or_die {
	my ($adt, $expected_tag) = @_;
	die "$adt not ADT"							unless ($adt isa Types::Algebraic::ADT);
	die $adt->{tag} . " neni $expected_tag"		unless ($expected_tag eq $adt->{tag});
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

