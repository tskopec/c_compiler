package CodeGen;

use strict;
use warnings;
use feature qw(say isa state current_sub signatures);

use List::Util qw(min);
use ADT::AlgebraicTypes qw(:TAC :ASM);
use Semantics;
use TypeUtils qw(/^MAX_/ get_type is_signed);

our %asm_symbol_table;

my @arg_regs = (ASM_DI(), ASM_SI(), ASM_DX(), ASM_CX(), ASM_R8(), ASM_R9());

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
		my $attrs = $entry->{attrs};
		if ($entry->{type}->is('T_FunType')) {
			$asm_symbol_table{$name} = {
				entry_type => 'Fun',
				defined => $attrs->get('defined')
			};
		} else {
			$asm_symbol_table{$name} = {
				entry_type => 'Obj',
				op_size => asm_type_of($entry->{type}),
				static => 0 + ($attrs->is('A_StaticAttrs'))
			};
		}
	}
}

#1# FIRST PASS ###
sub translate_to_ASM {
	my $node = shift;
	$node->match({
		TAC_Program => sub($declarations) {
			return ASM_Program([ map { translate_to_ASM($_) } @$declarations ]);
		},
		TAC_Function => sub($ident, $global, $params, $instructions) {
			my $move_to_stack = sub {
				my $param_i = shift;
				my $src = ($param_i <= $#arg_regs)
					? ASM_Reg($arg_regs[$param_i])
					: ASM_Stack(16 + 8 * ($param_i - @arg_regs));
				my $op_size = asm_type_of(Semantics::get_symbol_attr($params->[$param_i], 'type'));
				ASM_Mov($op_size, $src, ASM_Pseudo($params->[$param_i]));
			};
			return ASM_Function(
				$ident,
				$global,
				[ (map { $move_to_stack->($_) } (keys @$params)),
					(map { translate_to_ASM($_) } @$instructions) ]
			);
		},
		TAC_StaticVariable => sub($name, $global, $type, $init) {
			return ASM_StaticVariable($name, $global, size_in_bytes(asm_type_of($type)), $init);
		},
		TAC_Return => sub($value) {
			return (ASM_Mov(asm_type_of($value), translate_to_ASM($value), ASM_Reg(ASM_AX())),
				ASM_Ret());
		},
		TAC_Unary => sub($op, $src, $dst) {
			my $asm_dst = translate_to_ASM($dst);
			if ($op->is('TAC_Not')) {
				return (ASM_Cmp(asm_type_of($src), ASM_Imm(0), translate_to_ASM($src)),
					ASM_Mov(asm_type_of($dst), ASM_Imm(0), $asm_dst),
					ASM_SetCC(ASM_E(), $asm_dst));
			}
			my $src_op_size = asm_type_of($src);
			return (ASM_Mov($src_op_size, translate_to_ASM($src), $asm_dst),
				ASM_Unary(convert_unop($op), $src_op_size, $asm_dst));
		},
		TAC_Binary => sub($op, $src1, $src2, $dst) {
			my $asm_dst = translate_to_ASM($dst);
			my $src_asm_type = asm_type_of($src1);
			if (-1 != (my $i = $op->index_of_in(qw(TAC_Divide TAC_Modulo)))) {
				return (
					ASM_Mov($src_asm_type, translate_to_ASM($src1), ASM_Reg(ASM_AX())),
					(is_signed(get_type($src1)) ? (
						ASM_Cdq($src_asm_type),
						ASM_Idiv($src_asm_type, translate_to_ASM($src2))
					) : (
						ASM_Mov($src_asm_type, ASM_Imm(0), ASM_Reg(ASM_DX())),
						ASM_Div($src_asm_type, translate_to_ASM($src2)))
					),
					ASM_Mov($src_asm_type, ASM_Reg((ASM_AX(), ASM_DX())[$i]), $asm_dst));
			} elsif (-1 != ($i = $op->index_of_in(qw(TAC_Equal TAC_NotEqual TAC_LessThan TAC_LessOrEqual TAC_GreaterThan TAC_GreaterOrEqual)))) {
				state @codes = (
					[ ASM_E(), ASM_NE(), ASM_B(), ASM_BE(), ASM_A(), ASM_AE() ], # unsigned
					[ ASM_E(), ASM_NE(), ASM_L(), ASM_LE(), ASM_G(), ASM_GE() ]  # signed
				);
				return (ASM_Cmp($src_asm_type, translate_to_ASM($src2), translate_to_ASM($src1)),
					ASM_Mov(asm_type_of($dst), ASM_Imm(0), $asm_dst),
					ASM_SetCC($codes[is_signed(get_type($src1))]->[$i], $asm_dst));
			} else {
				return (ASM_Mov($src_asm_type, translate_to_ASM($src1), $asm_dst),
					ASM_Binary(convert_binop($op), $src_asm_type, translate_to_ASM($src2), $asm_dst));
			}
		},
		TAC_JumpIfZero => sub($val, $target) {
			return (ASM_Cmp(asm_type_of($val), ASM_Imm(0), translate_to_ASM($val)),
				ASM_JmpCC(ASM_E(), $target));
		},
		TAC_JumpIfNotZero => sub($val, $target) {
			return (ASM_Cmp(asm_type_of($val), ASM_Imm(0), translate_to_ASM($val)),
				ASM_JmpCC(ASM_NE(), $target));
		},
		TAC_Jump => sub($target) {
			return ASM_Jmp($target);
		},
		TAC_Label => sub($ident) {
			return ASM_Label($ident);
		},
		TAC_Copy => sub($src, $dst) {
			return ASM_Mov(asm_type_of($src), translate_to_ASM($src), translate_to_ASM($dst));
		},
		TAC_FunCall => sub($ident, $args, $dst) {
			my (@instructions, @reg_args, @stack_args);
			(@reg_args[0 .. ($#$args < 5 ? $#$args : 5)], @stack_args) = @$args;
			my $stack_padding = 8 * (@stack_args % 2);
			if ($stack_padding) {
				push(@instructions, allocate_stack($stack_padding));
			}
			while (my ($i, $tac_arg) = each @reg_args) {
				my $asm_arg = translate_to_ASM($tac_arg);
				push(@instructions, ASM_Mov(asm_type_of($tac_arg), $asm_arg, ASM_Reg($arg_regs[$i])));
			}
			for my $tac_arg (reverse @stack_args) {
				my $asm_arg = translate_to_ASM($tac_arg);
				if ($asm_arg->is(qw(ASM_Imm ASM_Reg)) || (asm_type_of($tac_arg))->is('ASM_Quadword')) {
					push(@instructions, ASM_Push($asm_arg));
				} else {
					push(@instructions, (ASM_Mov(ASM_Longword(), $asm_arg, ASM_Reg(ASM_AX())),
						ASM_Push(ASM_Reg(ASM_AX()))));
				}
			}
			push(@instructions, ASM_Call($ident));
			my $remove_bytes = 8 * @stack_args + $stack_padding;
			if ($remove_bytes) {
				push(@instructions, deallocate_stack($remove_bytes));
			}
			push(@instructions, ASM_Mov(asm_type_of($dst), ASM_Reg(ASM_AX()), translate_to_ASM($dst)));
			return @instructions;
		},
		TAC_Constant => sub($const) {
			return ASM_Imm($const->get('val'));
		},
		TAC_Variable => sub($ident) {
			return ASM_Pseudo($ident);
		},
		TAC_SignExtend => sub($src, $dst) {
			return ASM_Movsx(translate_to_ASM($src), translate_to_ASM($dst));
		},
		TAC_Truncate => sub($src, $dst) {
			return ASM_Mov(ASM_Longword(), translate_to_ASM($src), translate_to_ASM($dst));
		},
		TAC_ZeroExtend => sub($src, $dst) {
			return ASM_MovZeroExtend(translate_to_ASM($src), translate_to_ASM($dst));
		},
		default => sub { die "unknown TAC $node" }
	});
}

sub allocate_stack {
	return ASM_Binary(ASM_Sub(), ASM_Quadword(), ASM_Imm(shift()), ASM_Reg(ASM_SP()));
}
sub deallocate_stack {
	return ASM_Binary(ASM_Add(), ASM_Quadword(), ASM_Imm(shift()), ASM_Reg(ASM_SP()));
}

sub convert_unop {
	my $op = shift;
	$op->match({
		TAC_Complement => sub() { return ASM_Not() },
		TAC_Negate => sub() { return ASM_Neg() },
		default => sub { die "unknown op $op" },
	});
}

sub convert_binop {
	my $op = shift;
	$op->match({
		TAC_Add => sub() { return ASM_Add() },
		TAC_Subtract => sub() { return ASM_Sub() },
		TAC_Multiply => sub() { return ASM_Mult() },
		default => sub { die "unknown bin op $op" },
	});
}

sub asm_type_of {
	my $val = shift;
	my $type = $val->is('T_Type') ? $val : get_type($val);
	return $type->match({
		"T_Int, T_UInt" => ASM_Longword(),
		"T_Long, T_ULong" => ASM_Quadword(),
		default => => sub() { die "unknown type $val" }
	});
}

sub size_in_bytes {
	my $type = shift;
	return 4 if ($type->is('ASM_Longword'));
	return 8 if ($type->is('ASM_Quadword'));
	die "unknown type $type";
}


#2# SECOND PASS ###
sub fix_up {
	my $program = shift;
	for my $declaration (@{$program->get('declarations')}) {
		$declaration->match({
			ASM_Function => sub($name, $global, $instructions) {
				replace_pseudo($declaration);
				fix_instr($declaration);
			},
			ASM_StaticVariable => sub($name, $global, $alignment, $init) { ; },
			default => sub { die "not a declaration: $declaration" }
		});
	}
}

sub replace_pseudo {
	my ($function, %offsets) = (shift(), ());
	my $current_offset = 0;
	my $process_node;
	$process_node = sub {
		my $node = shift;
		return $node->match({
			ASM_Pseudo => sub($ident) {
				if (exists $asm_symbol_table{$ident} && $asm_symbol_table{$ident}->{static}) {
					return ASM_Data($ident);
				} else {
					unless (exists $offsets{$ident}) {
						my $size = size_in_bytes($asm_symbol_table{$ident}{op_size});
						$offsets{$ident} = ($current_offset -= $size + $current_offset % $size);
					}
					return ASM_Stack($offsets{$ident});
				}
			},
			default => sub {
				$node->remap_values(sub {
					my $val = shift;
					if ($val isa 'ADT::ADT') {
						$val = $process_node->($val);
					} elsif (ref($val) eq 'ARRAY') {
						$val = [ map { $process_node->($_) } @$val ];
					}
					return $val;
				});
				return $node;
			}
		});
	};
	$process_node->($function);
	my ($name, $global, $instructions) = $function->values_in_order('ASM_Function');
	my $max_offset = -$current_offset;
	unshift(@$instructions, allocate_stack(16 * int(($max_offset + 15) / 16))); # 16 byte aligned
}

#3# FIX
sub fix_instr {
	my $function = shift;
	my $fix = sub {
		my $instruction = shift;
		my $res = [ $instruction ];
		$instruction->match({
			ASM_Binary => sub($op, $op_size, $src, $dst) {
				if ($op->is('ASM_Mult')) {
					if (check_imm_too_large($src, $op_size)) {
						$res = relocate_instr_operand($res, { when => 'before', from => $src, to => ASM_R10(), op_size => $op_size });
					}
					if (is_mem_addr($dst)) {
						$res = relocate_instr_operand($res, { when => 'both', from => $dst, to => ASM_R11(), op_size => $op_size });
					}
				} elsif ($op->is('ASM_Add', 'ASM_Sub')) {
					if ((is_mem_addr($src) && is_mem_addr($dst)) || check_imm_too_large($src, $op_size)) {
						$res = relocate_instr_operand($res, { when => 'before', from => $src, to => ASM_R10(), op_size => $op_size });
					}
				}
			},
			ASM_Mov => sub($op_size, $src, $dst) {
				if (is_mem_addr($src) && is_mem_addr($dst)) {
					$res = relocate_instr_operand($res, { when => 'before', from => $src, to => ASM_R10(), op_size => $op_size });
				} elsif ($src->is('ASM_Imm')) {
					if ($op_size->is('ASM_Longword')) {
						$src->set('val', $src->get('val') & 0xffffffff);
					} elsif ($op_size->is('ASM_Quadword') && $src->get('val') > MAX_INT) {
						$res = relocate_instr_operand($res, { when => 'before', from => $src, to => ASM_R10(), op_size => $op_size });
					}
				}
			},
			ASM_Cmp => sub($op_size, $src, $dst) {
				if ((is_mem_addr($src) && is_mem_addr($dst)) || check_imm_too_large($src, $op_size)) {
					$res = relocate_instr_operand($res, { when => 'before', from => $src, to => ASM_R10(), op_size => $op_size });
				}
				if ($dst->is('ASM_Imm')) {
					$res = relocate_instr_operand($res, { when => 'before', from => $dst, to => ASM_R11(), op_size => $op_size });
				}
			},
			"ASM_Idiv, ASM_Div" => sub($op_size, $operand) {
				if ($operand->is('ASM_Imm')) {
					$res = relocate_instr_operand($res, { when => 'before', from => $operand, to => ASM_R10(), op_size => $op_size });
				}
			},
			ASM_Movsx => sub($src, $dst) {
				if ($src->is('ASM_Imm')) {
					$res = relocate_instr_operand($res, { when => 'before', from => $src, to => ASM_R10(), op_size => ASM_Longword() });
				}
				if (is_mem_addr($dst)) {
					$res = relocate_instr_operand($res, { when => 'after', from => ASM_R11(), to => $dst, op_size => ASM_Quadword() });
				}
			},
			ASM_MovZeroExtend => sub($src, $dst) {
				if ($dst->is('ASM_Reg')) {
					$res = [ ASM_Mov(ASM_Longword(), $src, $dst) ];
				} else {
					$res = relocate_instr_operand([ ASM_Mov(ASM_Quadword(), $src, $dst) ], { when => 'before', from => $src, to => ASM_R11(), op_size => ASM_Longword() });
				}
			},
			ASM_Push => sub($operand) {
				if (check_imm_too_large($operand, ASM_Quadword())) {
					$res = relocate_instr_operand($res, { when => 'before', from => $operand, to => ASM_R10(), op_size => ASM_Quadword() });
				}
			},
			default => sub { ; }
		});
		return @$res;
	};
	my ($name, $global, $instructions) = $function->values_in_order('ASM_Function');
	$function->set('instructions', [ map { $fix->($_) } @$instructions ]);
}

# FIX utils
sub is_mem_addr {
	return (shift())->is('ASM_Stack', 'ASM_Data');
}

# The assembler permits an immediate value in addq, imulq, subq, cmpq, or pushq only if it can be represented as a signed 32-bit integer (page 268)
sub check_imm_too_large {
	my ($src, $op_size) = @_;
	return $op_size->is('ASM_Quadword') && $src->is('ASM_Imm') && $src->get('val') > MAX_INT;
}

sub relocate_instr_operand {
	my ($instructions, $move) = @_;
	if (%$move) {
		my $instruction = $instructions->[-1];
		my ($from, $to) = map { $_->is('ASM_Register') ? ASM_Reg($_) : $_ } (@$move{'from', 'to'});
		if ($move->{when} eq 'before') {
			unshift(@$instructions, ASM_Mov($move->{op_size}, $from, $to));
			$instruction->remap_values(sub {
				my $val = shift;
				$val eq $from ? $to : $val
			});
		} elsif ($move->{when} eq 'after') {
			push(@$instructions, ASM_Mov($move->{op_size}, $from, $to));
			$instruction->remap_values(sub {
				my $val = shift;
				$val eq $to ? $from : $val
			});
		} elsif ($move->{when} eq 'both') {
			unshift(@$instructions, ASM_Mov($move->{op_size}, $from, $to));
			$instruction->remap_values(sub {
				my $val = shift;
				$val eq $from ? $to : $val
			});
			push(@$instructions, ASM_Mov($move->{op_size}, $to, $from));
		}
	}
	return $instructions;
}

1;
