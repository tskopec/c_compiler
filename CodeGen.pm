package CodeGen;

use strict;
use warnings;
use feature qw(say isa state current_sub);
use List::Util qw(min);
use Types::Algebraic;
use Semantics;

our %asm_symbol_table;

my @arg_regs = (::DI(), ::SI(), ::DX(), ::CX(), ::R8(), ::R9());

sub generate {
	my $tac = shift;
	my $asm = translate_to_ASM($tac);
	fill_asm_symtable();
	fix_up($asm);
	return $asm;
}

sub fill_asm_symtable {
	%asm_symbol_table = ();
	while (my ($name, $entry) = each %Semantics::symbol_table) {
		if ($entry->{type}{tag} eq 'FunType') {
			$asm_symbol_table{$name} = { 
				entry_type => 'Fun',
			   	defined => $entry->{attrs}{defined}
		   	};
		} else {
			$asm_symbol_table{$name} = { 
				entry_type => 'Obj',
			   	op_size => operand_size_of($entry->{type}),
			   	static => 0+($entry->{attrs}{tag} eq 'StaticAttrs') 
			};
		}
	}	 
}

### FIRST PASS ###
sub translate_to_ASM {
	my $node = shift;
	match ($node) {
		with (TAC_Program $declarations) {
			return ::ASM_Program([ map { translate_to_ASM($_) } @$declarations]);
		}
		with (TAC_Function $ident $global $params $instructions) {
			my $move_to_stack = sub {
				my $param_i = shift;
				my $src = ($param_i <= $#arg_regs) 
					? ::ASM_Reg($arg_regs[$param_i])
					: ::ASM_Stack(16 + 8 * ($param_i - @arg_regs));
				my $op_size = operand_size_of(Semantics::get_symbol_attr($params->[$param_i], 'type'));
				::ASM_Mov($op_size, $src, ::ASM_Pseudo($params->[$param_i]));
			};
			return ::ASM_Function(
				$ident,
				$global,
				[ (map { $move_to_stack->($_) } (keys @$params)),
				  (map { translate_to_ASM($_) } @$instructions)	]
			);
		}
		with (TAC_StaticVariable $name $global $type $init) {
			return ::ASM_StaticVariable($name, $global, size_in_bytes(operand_size_of($type)), $init);
		}
		with (TAC_Return $value) {
			return (::ASM_Mov(operand_size_of($value), translate_to_ASM($value), ::ASM_Reg(::AX())),
					::ASM_Ret());
		}
		with (TAC_Unary $op $src $dst) {
			my $asm_dst = translate_to_ASM($dst);
			if ($op->{tag} eq 'TAC_Not') {
				return (::ASM_Cmp(operand_size_of($src), ::ASM_Imm(0), translate_to_ASM($src)),
						::ASM_Mov(operand_size_of($dst), ::ASM_Imm(0), $asm_dst),
						::ASM_SetCC(::E(), $asm_dst));
			}
			my $src_op_size = operand_size_of($src);
			return (::ASM_Mov($src_op_size, translate_to_ASM($src), $asm_dst),
					::ASM_Unary(convert_unop($op), $src_op_size, $asm_dst));
		}
		with (TAC_Binary $op $src1 $src2 $dst) {
			my $asm_dst = translate_to_ASM($dst);
			my $src_op_size = operand_size_of($src1);
			if (-1 != (my $i = ::index_of_in($op, qw(TAC_Divide TAC_Modulo)))) {
				return (::ASM_Mov($src_op_size, translate_to_ASM($src1), ::ASM_Reg(::AX())),
						::ASM_Cdq($src_op_size),
						::ASM_Idiv($src_op_size, translate_to_ASM($src2)),
						::ASM_Mov($src_op_size, ::ASM_Reg((::AX(), ::DX())[$i]), $asm_dst));
			} elsif (-1 != (my $i = ::index_of_in($op, qw(TAC_Equal TAC_NotEqual TAC_LessThan TAC_LessOrEqual TAC_GreaterThan TAC_GreaterOrEqual)))) {
				return (::ASM_Cmp($src_op_size, translate_to_ASM($src2), translate_to_ASM($src1)),
						::ASM_Mov(operand_size_of($dst), ::ASM_Imm(0), $asm_dst),
						::ASM_SetCC((::E(), ::NE(), ::L(), ::LE(), ::G(), ::GE())[$i], $asm_dst));
			} else {
				return (::ASM_Mov($src_op_size, translate_to_ASM($src1), $asm_dst),
						::ASM_Binary(convert_binop($op), $src_op_size, translate_to_ASM($src2), $asm_dst));
			}
		}
		with (TAC_JumpIfZero $val $target) {
			return (::ASM_Cmp(operand_size_of($val), ::ASM_Imm(0), translate_to_ASM($val)),
					::ASM_JmpCC(::E(), $target));
		}
		with (TAC_JumpIfNotZero $val $target) {
			return (::ASM_Cmp(operand_size_of($val), ::ASM_Imm(0), translate_to_ASM($val)),
					::ASM_JmpCC(::NE(), $target));
		}
		with (TAC_Jump $target) {
			return ::ASM_Jmp($target);
		}
		with (TAC_Label $ident) {
			return ::ASM_Label($ident);
		}
		with (TAC_Copy $src $dst) {
			return ::ASM_Mov(operand_size_of($src), translate_to_ASM($src), translate_to_ASM($dst));
		}
		with (TAC_FunCall $ident $args $dst) {
			my (@instructions, @reg_args, @stack_args);
			(@reg_args[0..($#$args < 5 ? $#$args : 5)], @stack_args) = @$args;
			my $stack_padding = 8 * (@stack_args % 2);
			if ($stack_padding) {
				push(@instructions, allocate_stack($stack_padding));
			}	
			while (my ($i, $tac_arg) = each @reg_args) {
				my $asm_arg = translate_to_ASM($tac_arg);
				push(@instructions, ::ASM_Mov(operand_size_of($asm_arg), $asm_arg, ::ASM_Reg($arg_regs[$i])));
			}
			for my $tac_arg (reverse @stack_args) {
				my $asm_arg = translate_to_ASM($tac_arg);
				if (::is_one_of($asm_arg, qw(ASM_Imm ASM_Reg)) || ::is_one_of(operand_size_of($asm_arg), 'ASM_Quadword')) {
					push(@instructions, ::ASM_Push($asm_arg));
				} else {
					push(@instructions, (::ASM_Mov(::ASM_Longword(), $asm_arg, ::ASM_Reg(::AX())),
										 ::ASM_Push(::ASM_Reg(::AX()))));
				}
			}
			push(@instructions, ::ASM_Call($ident));
			my $remove_bytes = 8 * @stack_args + $stack_padding;
			if ($remove_bytes) {
				push(@instructions, deallocate_stack($remove_bytes));
			}
			push(@instructions, ::ASM_Mov(operand_size_of($dst), ::ASM_Reg(::AX()), translate_to_ASM($dst)));
			return @instructions;
		}
		with (TAC_Constant $int) {
			return ::ASM_Imm($int);
		}
		with (TAC_Variable $ident) {
			return ::ASM_Pseudo($ident);
		}
		with (TAC_SignExtend $src $dst) {
			return ::ASM_Movsx(translate_to_ASM($src), translate_to_ASM($dst));
		}
		with (TAC_Truncate $src $dst) {
			return ::ASM_Mov(::ASM_Longword(), translate_to_ASM($src), translate_to_ASM($dst));
		}
		default { die "unknown TAC $node" }
	}
}

sub convert_unop {
	my $op = shift;
	match ($op) {
		with (TAC_Complement)	{ return ::ASM_Not }
		with (TAC_Negate)		{ return ::ASM_Neg }
		default					{ die "unknown op $op" }
	}	
}

sub convert_binop {
	my $op = shift;
	match ($op) {
		 with (TAC_Add)			{ return ::ASM_Add }
		 with (TAC_Subtract)	{ return ::ASM_Sub }
		 with (TAC_Multiply)	{ return ::ASM_Mult }
		 default				{ die "unknown bin op $op" }
	}	
}

sub operand_size_of {
	my $val = shift;
	my $type_tag;
	if (ref($val) eq 'Type') {
		$type_tag = $val->{tag};
	} else {
		match ($val) {
			with (TAC_Constant $const) {
				$type_tag = $const->{tag};
			}
			with (TAC_Variable $name) {
				$type_tag = $Semantics::symbol_table{$name}->{type}{tag};
			}
			default {
				die "unknown val $val (operand_size_of)";
			}
		}
	}
	return ::ASM_Longword() if ($type_tag =~ /Int/);
	return ::ASM_Quadword() if ($type_tag =~ /Long/);
}

sub size_in_bytes {
	my $type = shift;
	return 4 if ($type->{tag} eq 'ASM_Longword');
	return 8 if ($type->{tag} eq 'ASM_Quadword');
	die "unknown type $type (size_in_bytes)";
}

sub allocate_stack {
	return ::ASM_Binary(::ASM_Sub(), ::ASM_Quadword(), ::ASM_Imm(shift()), ::ASM_Reg(::SP()));
}
sub deallocate_stack {
	return ::ASM_Binary(::ASM_Add(), ::ASM_Quadword(), ::ASM_Imm(shift()), ::ASM_Reg(::SP()));
}


### SECOND PASS ###
sub fix_up {
	my $program = shift;
	for my $declaration ($program->{values}[0]->@*) {
		match ($declaration) {
			with (ASM_Function $name $global $instructions) {
				replace_pseudo($declaration);
				fix_instr($declaration);
			}
			with (ASM_StaticVariable $name $global $alignment $init) {;}
			default { die "not a declaration: $declaration" }
		}
	}
}

sub replace_pseudo {
	my ($function, %offsets) = (shift(), ());
	my $current_offset = 0;
	my $process_node;
	$process_node = sub {
		my $node = shift;
		match ($node) {
			with (ASM_Pseudo $ident) {
				if (exists $asm_symbol_table{$ident} && $asm_symbol_table{$ident}->{static}) {
					return ::ASM_Data($ident);
				} else {
					unless (exists $offsets{$ident}) {
						my $size = size_in_bytes($asm_symbol_table{$ident}{op_size});
						$offsets{$ident} = ($current_offset -= $size + $current_offset % $size);				
					}	
					return ::ASM_Stack($offsets{$ident});
				}
			}
			default { 
				for my $val ($node->{values}->@*) {
					if ($val isa Types::Algebraic::ADT) {
						$val = $process_node->($val);
					} elsif (ref($val) eq 'ARRAY') {
						$val = [ map { $process_node->($_) } @$val ];
					}
				}
				return $node;
			}
		}
	};
	$process_node->($function);
	my ($name, $global, $instructions) = ::extract_or_die($function, 'ASM_Function');
	my $max_offset = -$current_offset;
	unshift(@$instructions, allocate_stack($max_offset + ($max_offset % 16))); # 16 byte aligned
}

sub fix_instr {
	my $function = shift;
	my $fix = sub {
		my $instruction = shift;
		my $res = [$instruction];
		if (my ($op, $op_size, $src, $dst) = ::extract($instruction, 'ASM_Binary')) {
			if ($op->{tag} eq 'ASM_Mult') {
				if (check_too_large($src, $op_size)) {
					$res = relocate($res, { when => 'before', from => $src, to => ::R10(), op_size => $op_size });
				}
				if (is_mem_addr($dst)) {
					$res = relocate($res, { when => 'both', from => $dst, to => ::R11(), op_size => $op_size });
				}
			} elsif ($op->{tag} eq 'ASM_Add' || $op->{tag} eq 'ASM_Sub') {
				if ((is_mem_addr($src) && is_mem_addr($dst)) || check_imm_too_large($src, $op_size)) {
					$res = relocate($res, { when => 'before', from => $src, to => ::R10(), op_size => $op_size });
				} 
			}
		} elsif (my ($op_size, $src, $dst) = ::extract($instruction, 'ASM_Mov')) {
			if (is_mem_addr($src) && is_mem_addr($dst)) {
				$res = relocate($res, { when => 'before', from => $src, to => ::R10(), op_size => $op_size });
			}
		} elsif (my ($op_size, $src, $dst) = ::extract($instruction, 'ASM_Cmp')) {
			if ((is_mem_addr($src) && is_mem_addr($dst)) || check_imm_too_large($src, $op_size)) {
				$res = relocate($res, { when => 'before', from => $src, to => ::R10(), op_size => $op_size });
			}
			if ($dst->{tag} eq 'ASM_Imm') {
				$res = relocate($res, { when => 'before', from => $dst, to => ::R11(), op_size => $op_size });
			}
		}
		elsif (my ($op_size, $operand) = ::extract($instruction, 'ASM_Idiv')) {
			if ($operand->{tag} eq 'ASM_Imm') {
				$res = relocate($res, { when => 'before', from => $operand, to => ::R10(), op_size => $op_size });
			}
		} elsif (my ($src, $dst) = ::extract($instruction, 'ASM_Movsx')) {
			if ($src->{tag} eq 'ASM_Imm') {
				$res = relocate($res, { when => 'before', from => $src, to => ::R10(), op_size => ::ASM_Longword() });
			}
			if (is_mem_addr($dst)) {
				$res = relocate($res, { when => 'after', from => ::R11(), to => $dst, op_size => ::ASM_Quadword() });
			}
		} elsif (my ($operand) = ::extract($instruction, 'ASM_Push')) {
			if (check_imm_too_large($operand, ::ASM_Quadword())) {
				$res = relocate($res, { when => 'before', from => $operand, to => ::R10(), op_size => ::ASM_Quadword() });
			}
		}
		return @$res;
	};
	my ($name, $global, $instructions) = ::extract_or_die($function, 'ASM_Function');
	splice(@$instructions, 0, $#$instructions + 1, ( map { $fix->($_) } @$instructions ));
}

# FIX utils
sub is_mem_addr {
	return ::is_one_of(shift(), 'ASM_Stack', 'ASM_Data');
}

# The assembler permits an immediate value in addq, imulq, subq, cmpq, or pushq only if it can be represented as a signed 32-bit integer (page 268)
sub check_imm_too_large {
	my ($src, $op_size) = @_;
	return ($op_size->{tag} eq 'ASM_Quadword' && $src->{tag} eq 'ASM_Imm' && $src->{values}[0] > (2**31 - 1));
}

sub relocate {
	my ($instructions, $move) = @_;
	if (%$move) {
		my $instruction = $instructions->[-1];
		my $from = ref($move->{from}) eq 'ASM_Register' ? ::ASM_Reg($move->{from}) : $move->{from};
		my $to = ref($move->{to}) eq 'ASM_Register' ? ::ASM_Reg($move->{to}) : $move->{to};
		if ($move->{when} eq 'before') {
			unshift(@$instructions, ::ASM_Mov($move->{op_size}, $from, $to));
			for my $val ($instruction->{values}->@*) {
				$val = $to if ($val eq $from);
			}
		} elsif ($move->{when} eq 'after') {
			push(@$instructions, ::ASM_Mov($move->{op_size}, $from, $to));
			for my $val ($instruction->{values}->@*) {
				$val = $from if ($val eq $to);
			}
		} elsif ($move->{when} eq 'both') {
			unshift(@$instructions, ::ASM_Mov($move->{op_size}, $from, $to));
			for my $val ($instruction->{values}->@*) {
				$val = $to if ($val eq $from);
			}
			push(@$instructions, ::ASM_Mov($move->{op_size}, $to, $from));
		}
	}
	return $instructions;
}

1;
