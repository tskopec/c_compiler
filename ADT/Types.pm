package Types;
use strict;
use warnings;
use feature qw(say);

use ParseASDL;

BEGIN {
# LEX
	declare(q{ Token
	   	= Identifier(String name)
		| IntConstant(Int val)
		| LongConstant(Int val)
		| Keyword(String word)
		| Symbol(String char)
		| Operator(String op)
	});


#	declare("Token", [
#		Identifier => [name => "string"],
#		IntConstant => [val => "int"],
#		LongConstant => [val => "int"],
#		Keyword => [word => "string"],
#		Symbol => [char => "string"],
#		Operator => [op => "string"],
#	]);

## AST
#	declare('AST_Program', [
#		AST_Program => [declarations => 'AST_Declaration*']	
#	]);
#	declare('AST_Declaration', [
#		AST_VarDeclaration => [name => 'string', init => 'AST_Expression?', type => 'Type', storage => 'StorageClass?'],
#		AST_FunDeclaration => [name => 'string', params => 'AST_VarDeclaration*', body => 'AST_Block?', type => 'Type', storage => 'StorageClass?'],	
#	]);
#	declare('AST_Block', [
#		'AST_Block' => [ blockItems => 'AST_Statement|AST_Declaration'],	
#	]);
#	declare('AST_Statement', [
#		'AST_Null',
#		AST_Return => [val => 'AST_Expression'],
#		AST_If => [cond => 'AST_Expression', then => 'AST_Statement', else => 'AST_Statement?'],
#		AST_Compound => [block => 'AST_Block'],
#		AST_Break => [label => 'string'],
#		AST_Continue => [label => 'string'],
#		AST_While => [cond => 'AST_Expression', body => 'AST_Statement', label => 'string'],
#		AST_DoWhile => [body => 'AST_Statement', cond => 'AST_Expression', label => 'string'],
#		AST_For => [intit => 'AST_ForInit', cond => 'AST_Expression?', post => 'AST_Expression?', body => 'AST_Statement', label => 'string']
#		# TODO forinit
#	]);
#	declare('AST_Expression', [
#		AST_ConstantExpression => [constant => 'AST_Constant', type => 'Type'],
#		AST_Var => [ident => 'string', type => 'Type'],
#		AST_Cast => [expr => 'AST_Expression', target => 'Type'],
#		AST_Unary => [op => 'AST_UnaryOperator', expr => 'AST_Expression', type => 'Type'],
#		AST_Binary => [op => 'AST_BinaryOperator', e1 => 'AST_Expression', e2 => 'AST_Expression', type => 'Type'],
#		AST_Assignment => [lhs => 'AST_Expression', rhs => 'AST_Expression', type => 'Type'],
#		AST_Conditional => [cond => 'AST_Expression', then => 'AST_Expression', else => 'AST_Expression'],
#		AST_FunctionCall => [ident => 'string', args => 'AST_Expression*', type => 'Type'],	
#	]);
#	declare('AST_UnaryOperator', [
#		'Complement', 'Negate', 'Not',	
#	]);
#	declare('AST_BinaryOperator', [
#		'Add', 'Subtract', 'Multiply', 'Divide', 'Modulo', 'And', 'Or', 'Equal', 'NotEqual', 'LessThan', 'LessOrEqual', 'GreaterThan', 'GreaterOrEqual'
#	]);
#	declare('AST_Constant', [
#		AST_ConstInt => [val => 'int'],
#		AST_ConstLong => [val => 'int'],	
#	]);
#
## Types & misc
#	declare('Type', [
#		'Int',
#	   	'Long',
#	   	FunType => [params => 'Type*', ret => 'Type']	
#	]);
#	declare('IdentifierAttrs', [
#		FunAttrs => [defined => 'bool', global => 'bool'],
#		StaticAttrs => [init_val => 'InitialValue', gloabl => 'bool'],	
#		'LocalAttrs',
#	]);
#	declare('Initialvalue', [
#		'Tentative', Initial => [statInit => 'StaticInit'], 'NoInitializer',	
#	]);
#	declare('StaticInit', [
#		IntInit => [val => 'int'], LongInit => [val => 'int'],
#	]);
#	declare('StorageClass', [
#		'Static', 'Extern'
#	]);
#
}

sub import {
	shift;
	ParseASDL->import(@_);
}

1;
