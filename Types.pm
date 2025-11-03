package Types;
use strict;
use warnings;

use ADT::ParseASDL;

BEGIN {

# Lex ###
	declare(q{
		Lex_Token =
			Lex_Identifier(String name)
			| Lex_IntConstant(Integer val)
			| Lex_LongConstant(Integer val)
			| Lex_Keyword(String word)
			| Lex_Symbol(String char)
			| Lex_Operator(String op)
	});

# AST ###
	declare(q{
		AST_Program =
			AST_Program(AST_Declaration* declarations)
	});
	declare(q{
		AST_Declaration =
			AST_VarDeclaration(String name, AST_Expression? initializer, Type type, StorageClass? storage)
			| AST_FunDeclaration(String name, AST_VarDeclaration* params, AST_Block? body, Type type, StorageClass? storage)
	});
	declare(q{
		AST_Block =
			AST_Block(AST_BlockItem* items)
	});
	declare(q{
		AST_BlockItem =
			AST_BlockStatement(AST_Statement stmt)
			| AST_BlockDeclaration(AST_Declaration decl)
	});
	declare(q{
		AST_Statement =
			AST_Null
			| AST_Return(AST_Expression expr)
			| AST_ExprStatement(AST_Expression expr)
			| AST_If(AST_Expression cond, AST_Statement then, AST_Statement? else)
			| AST_Compound(AST_Block block)
			| AST_Break(String label)
			| AST_Continue(String label)
			| AST_While(AST_Expression cond, AST_Statement body, String label)
			| AST_DoWhile(AST_Statement body, AST_Expression cond, String label)
			| AST_For(AST_ForInit init, AST_Expression? cond, AST_Expression? post, Statement body, String label)
	});
	declare(q{
		AST_ForInit =
			AST_ForInitDeclaration(AST_VarDeclaration decl)
			| AST_ForInitExpr(AST_Expression? expr)
	});
	declare(q{
		AST_Expression =
			 AST_ConstantExpr(AST_Constant constant, Type type)
			 | AST_Var(String ident, Type type)
			 | AST_Cast(AST_Expression expr, Type target)
			 | AST_Unary(AST_UnaryOperator op, AST_Expression expr, Type type)
			 | AST_Binary(AST_BinaryOperator op, AST_Expression expr1, AST_Expression expr2, Type type)
			 | AST_Assignment(AST_Expression lhs, AST_Expression rhs, Type type)
			 | AST_Conditional(AST_Expression cond, AST_Expression then, AST_Expression else, Type type)
			 | AST_FunctionCall(String ident, AST_Expression args, Type type)
	});
	declare(q{
		AST_UnaryOperator =
			AST_Complement | AST_Negate | AST_Not
	});
	declare(q{
		AST_BinaryOperator =
			AST_Add | AST_Subtract | AST_Multiply | AST_Divide | AST_Modulo | AST_And | AST_Or | AST_Equal | AST_NotEqual | AST_LessThan | AST_LessOrEqual | AST_GreaterThan | AST_GreaterOrEqual
	});
	declare(q{
		AST_Constant =
			AST_ConstInt(Integer val)
			| AST_ConstLong(Integer val)
	});

# Types & misc
	declare(q{
		Type =
			Int
			| Long
			| FunType(Type* params, Type ret)
			| DummyType
	});
	declare(q{
		IdentifierAttrs =
			FunAttrs(Bool defined, Bool global)
			| StaticAttrs(InitialValue init_val, Bool global)
			| LocalAttrs
	});
	declare(q{
		InitialValue =
			Tentative
			| Initial(StaticInit static_init)
			| NoInitializer
	});
	declare(q{
		StaticInit =
			IntInit(Integer val)
			| LongInit(Integer val)
	});
	declare(q{
		StorageClass =
			Static | Extern
	});

# TAC ###
	declare(q{
		TAC_Program =
			TAC_Program(TAC_TopLevelDeclaration* declarations)
	});
	declare(q{
		TAC_TopLevelDeclaration =
			TAC_StaticVariable(String identifier, Bool global, Type type, StaticInit static_init)
			| TAC_Function(String identifier, Bool global, String* params, TAC_Instruction* instructions)
	});
	declare(q{
		TAC_Instruction =
			TAC_Return(TAC_Value value)
			| TAC_SignExtend(TAC_Value src, TAC_Value dst)
			| TAC_Truncate(TAC_Value src, TAC_Value dst)
			| TAC_Unary(TAC_UnaryOperator op, TAC_Value src, TAC_Value dst)
			| TAC_Binary(TAC_BinaryOperator op, TAC_Value val1, TAC_Value val2, TAC_Value dst)
			| TAC_Copy(TAC_Value src, TAC_Value dst)
			| TAC_Jump(String target)
			| TAC_JumpIfZero(TAC_Value cond, String target)
			| TAC_JumpIfNotZero(TAC_Value cond, String target)
			| TAC_Label(String ident)
			| TAC_FunCall(String name, TAC_Value* params, TAC_Value dst)
	});
	declare(q{
		TAC_Value =
			TAC_Constant(Constant constant)
			| TAC_Variable(String name)
	});
	declare(q{
		TAC_UnaryOperator =
			TAC_Complement | TAC_Negate | TAC_Not
	});
	declare(q{
		TAC_BinaryOperator =
			TAC_Add | TAC_Subtract | TAC_Multiply | TAC_Divide | TAC_Modulo | TAC_And | TAC_Or | TAC_Equal | TAC_NotEqual | TAC_LessThan | TAC_LessOrEqual | TAC_GreaterThan | TAC_GreaterOrEqual
	});

# ASM ###
	declare(q{
		ASM_Program =
			ASM_Program(ASM_TopLvlDeclaration* declarations)
	});
	declare(q{
		ASM_OperandSize =
			ASM_Longword | ASM_Quadword
	});
	declare(q{
		ASM_TopLevelDeclaration =
			ASM_StaticVariable(String name, Bool global, Integer alignment, StaticInit static_init)
			| ASM_Function(String name, Bool global, Instruction* instructions)
	});
	declare(q{
		ASM_Instruction =
			ASM_Mov(ASM_OperandSize opsize, ASM_Operand src, ASM_Operand dst)
			| ASM_Movsx(ASM_Operand src, ASM_Operand dst)
			| ASM_Unary(ASM_UnaryOperator op, ASM_OperandSize opsize, ASM_Operand operand)
			| ASM_Binary(ASM_BinaryOperator op, ASM_OperandSize opsize, ASM_Operand operand1, ASM_Operand operand2)
			| ASM_Cmp(ASM_OperandSize opsize, ASM_Operand operand1, ASM_Operand operand2)
			| ASM_Idiv(ASM_OperandSize opsize, ASM_Operand operand)
			| ASM_Cdq(ASM_OperandSize opsize)
			| ASM_Jmp(String String)
			| ASM_JmpCC(ASM_CondCode cond, String target)
			| ASM_SetCC(ASM_CondCode cond, ASM_Operand operand)
			| ASM_Label(String ident)
			| ASM_Push(ASM_Operand operand)
			| ASM_Call(String ident)
			| ASM_Ret
	});
	declare(q{
		ASM_UnaryOperator =
			ASM_Neg | ASM_Not
	});
	declare(q{
		ASM_BinaryOperator =
			ASM_Add | ASM_Sub | ASM_Mult
	});
	declare(q{
		ASM_Operand =
			ASM_Imm(Integer int)
			| ASM_Reg(ASM_Register reg)
			| ASM_Pseudo(String ident)
			| ASM_Stack(Integer offset)
			| ASM_Data(String ident)
	});
	declare(q{
		ASM_CondCode =
			E | NE | G | GE | L | LE
	});
	declare(q{
		ASM_Register =
			AX | CX | DX | DI | SI | R8 | R9 | R10 | R11 | SP
	});

}

sub import {
	shift;
	ADT::ParseASDL->import(@_);
}

1;
