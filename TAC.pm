package TAC;
use strict;
use warnings;
use feature qw(say state signatures);

use ADT::AlgebraicTypes qw(:AST :TAC :T);
use Semantics;


sub emit_TAC {
    my ($node, $instructions) = @_;
    $node->match({
        AST_Program => sub($declarations) {
            my (@tac_funs, @tac_vars);
            for my $d (@$declarations) {
                next if (not $d->is('AST_FunDeclaration');
                my $tac_fun = emit_TAC($d);
                push(@tac_funs, $tac_fun) if (defined $tac_fun);
            }
            @tac_vars = covert_symbols_to_TAC();
            return TAC_Program([@tac_vars, @tac_funs]);
        },
        AST_FunDeclaration => sub($name, $params, $body, $ret_type, $storage) {
            if (defined $body) {
                my $items = $body->get('items');
                my $instructions = [];
                for my $item (@$items) {
                    emit_TAC($item, $instructions);
                }
                push @$instructions, TAC_Return(TAC_Constant(AST_ConstInt(0))); # TODO predpona constant
                return TAC_Function($name,
                                      Semantics::get_symbol_attr($name, 'global'),
                                      [ map { $_->get('name') } @$params ],
                                      $instructions);
            } else {
                return undef;
            }
        },
        AST_VarDeclaration => sub($name, $init, $type, $storage) {
            if (defined $init) {
                emit_TAC(AST_Assignment(AST_Var($name, $type), $init, $type), $instructions);
            }
           },
        AST_Return => sub($exp) {
            push(@$instructions, TAC_Return(emit_TAC($exp, $instructions)));
        },
        AST_Null => sub() {;},
        AST_If => sub($cond, $then, $else) {
            my ($else_label) = labels('else') if defined $else;
            my ($end_label) = labels('end');
            my $cond_res = emit_TAC($cond, $instructions);
            push @$instructions, TAC_JumpIfZero($cond_res, defined $else ? $else_label : $end_label);
            emit_TAC($then, $instructions);
            push @$instructions, TAC_Jump($end_label);
            if (defined $else) {
                push @$instructions, TAC_Label($else_label);
                emit_TAC($else, $instructions);
            }
            push @$instructions, TAC_Label($end_label);
        },
        AST_Compound =>sub($block) {
            my ($items) = ::extract_or_die($block, 'Block');
            emit_TAC($_, $instructions) for @{$block->get('items')};
        },
        AST_DoWhile => sub($body, $cond, $label) {
            my ($start_label) = labels('start');
            push @$instructions, TAC_Label($start_label);
            emit_TAC($body, $instructions);
            push @$instructions, TAC_Label("_continue$label");
            my $cond_res = emit_TAC($cond, $instructions);
            push(@$instructions, (TAC_JumpIfNotZero($cond_res, $start_label),
                                  TAC_Label("_break$label")));
        },
        AST_While => sub($cond, $body, $label) {
            push @$instructions, TAC_Label("_continue$label");
            my $cond_res = emit_TAC($cond, $instructions);
            push @$instructions, TAC_JumpIfZero($cond_res, "_break$label");
            emit_TAC($body, $instructions);
            push(@$instructions, (TAC_Jump("_continue$label"),
                                  TAC_Label("_break$label")));
        },
        AST_For => sub($init, $cond, $post, $body, $label) {
            my ($start_label) = labels('start');
            emit_TAC($init, $instructions) if defined $init;
            push @$instructions, TAC_Label($start_label);
            if (defined $cond) {
                my $cond_res = emit_TAC($cond, $instructions);
                push @$instructions, TAC_JumpIfZero($cond_res, "_break$label");
            }
            emit_TAC($body, $instructions);
            push @$instructions, TAC_Label("_continue$label");
            emit_TAC($post, $instructions) if defined $post;
            push(@$instructions, (TAC_Jump($start_label),
                                  TAC_Label("_break$label")));
        },
        AST_Break => sub($label) {
            push @$instructions, TAC_Jump("_break$label");
        },
        AST_Continue =>sub($label) {
            push @$instructions, TAC_Jump("_continue$label");
        },
        AST_Expression => sub($expr) {
            emit_TAC($expr, $instructions);
        },
        AST_ConstantExpr => sub($const, $type) {
            return TAC_Constant($const);
        },
        AST_Var => sub($ident, $type) {
            return TAC_Variable($ident);
        },
        AST_Cast =>sub($expr, $type) {
            my $res = emit_TAC($expr, $instructions);
            if ($type->same_type_as(Semantics::get_type($expr)) {
                return $res;
            }
            my $dst = make_TAC_var($type);
            if ($type->is('T_Long')) {
                push(@$instructions, TAC_SignExtend($res, $dst));
            } else {
                push(@$instructions, TAC_Truncate($res, $dst));
            }
            return $dst;
        },
        AST_Unary =>sub($op, $exp, $type) {
            my $unop = convert_unop($op);
            my $src = emit_TAC($exp, $instructions);
            my $dst = make_TAC_var($type);
            push @$instructions, TAC_Unary($unop, $src, $dst);
            return $dst;
        },
        AST_Binary => sub($op, $exp1, $exp2, $type) {
            my $dst = make_TAC_var($type);
            if ($op->is('AST_And') {
                my ($false_label, $end_label) = labels(qw(false end));
                my $src1 = emit_TAC($exp1, $instructions);
                push @$instructions, TAC_JumpIfZero($src1, $false_label);
                my $src2 = emit_TAC($exp2, $instructions);
                push(@$instructions, TAC_JumpIfZero($src2, $false_label),
                                     TAC_Copy(TAC_Constant(AST_ConstInt(1)), $dst),   # TODO consts
                                     TAC_Jump($end_label),
                                     TAC_Label($false_label),
                                     TAC_Copy(TAC_Constant(AST_ConstInt(0)), $dst),
                                     TAC_Label($end_label));
            } elsif ($op->is('AST_Or') {
                my ($true_label, $end_label) = labels(qw(true end));
                my $src1 = emit_TAC($exp1, $instructions);
                push @$instructions, TAC_JumpIfNotZero($src1, $true_label);
                my $src2 = emit_TAC($exp2,  $instructions);
                push(@$instructions, TAC_JumpIfNotZero($src2, $true_label),
                                     TAC_Copy(TAC_Constant(AST_ConstInt(0)), $dst), # TODO consts
                                     TAC_Jump($end_label),
                                     TAC_Label($true_label),
                                     TAC_Copy(TAC_Constant(AST_ConstInt(1)), $dst),
                                     TAC_Label($end_label));
            } else {
                my $binop = convert_binop($op);
                my $src1 = emit_TAC($exp1, $instructions);
                my $src2 = emit_TAC($exp2, $instructions);
                push @$instructions, TAC_Binary($binop, $src1, $src2, $dst);
            }
            return $dst;
        },
        AST_Assignment => sub($var, $expr, $type) {
            my $tac_var = emit_TAC($var, $instructions);
            my $value = emit_TAC($expr, $instructions);
            push @$instructions, TAC_Copy($value, $tac_var);
            return $tac_var;
        },
        AST_Conditional => sub($cond, $then, $else, $type) {
            my $res = make_TAC_var($type);
            my ($e2_label, $end_label) = labels(qw(e2 end));
            my $cond_res = emit_TAC($cond, $instructions);
            push @$instructions, TAC_JumpIfZero($cond_res, $e2_label);
            my $e1_res = emit_TAC($then, $instructions);
            push @$instructions, (TAC_Copy($e1_res, $res),
                                  TAC_Jump($end_label),
                                   TAC_Label($e2_label));
            my $e2_res = emit_TAC($else, $instructions);
            push @$instructions, (TAC_Copy($e2_res, $res),
                                  TAC_Label($end_label));
            return $res;
        },
        AST_FunctionCall =>sub($name, $args, $type) {
            my $dst = make_TAC_var($type);
            my $arg_vals = [ map { emit_TAC($_, $instructions) } @$args ];
            push(@$instructions, (TAC_FunCall($name, $arg_vals, $dst)));
            return $dst;
        },
        default => sub() {
            die "unknown AST node: $node";
        }
    });
}

sub convert_unop {
    my $op = shift;
    state $map = {
        AST_Complement => TAC_Complement(),
        AST_Negate => TAC_Negate(),
        AST_Not => TAC_Not(),
    };
    return $map->{$op->{':tag'}} // die "unknown unop $op";
}

sub convert_binop {
    my $op = shift;
    state $map = {
         AST_Add => TAC_Add(),
         AST_Subtract => TAC_Subtract(),
         AST_Multiply => TAC_Multiply(),
         AST_Divide => TAC_Divide(),
         AST_Modulo => TAC_Modulo(),
         AST_And => TAC_And(),
         AST_Or => TAC_Or(),
         AST_Equal => TAC_Equal(),
         AST_NotEqual => TAC_NotEqual(),
         AST_LessThan => TAC_LessThan(),
         AST_LessOrEqual => TAC_LessOrEqual(),
         AST_GreaterThan => TAC_GreaterThan(),
         AST_GreaterOrEqual => TAC_GreaterOrEqual(),
    };
    return $map->{$op->{':tag'}} //  die "unknown bin op $op";
}

sub make_TAC_var {
    my $type = shift;
    my $name = temp_name();
    $Semantics::symbol_table{$name} = {
        type => $type, attrs => A_LocalAttrs()
    };
    return TAC_Variable($name);
}

sub temp_name {
    return "tmp." . $::global_counter++;
}

sub labels {
    my @res = map { "_${_}_" . $::global_counter } @_;
    $::global_counter++;
    return @res;
}

sub covert_symbols_to_TAC {
    my @tac_vars;
    while (my ($name, $entry) = each %Semantics::symbol_table) {
        if ($entry->{attrs}->is('A_StaticAttrs')) {
            my $type = $entry->{type};
            my ($stat_init, $global) = ($entry->{attrs})->values_in_order('A_StaticAttrs');
            $stat_init->match({
                I_Initial => sub($init) {
                    push(@tac_vars, TAC_StaticVariable($name, $global, $type, $init));
                },
                I_Tentative => sub() {
                    push(@tac_vars, TAC_StaticVariable($name, $global, $type, get_default_init($type)));
                },
                I_NoInitializer => sub() {;}
            });
        }
    }
    return @tac_vars;
}

sub get_default_init {
    my $type = shift;
    return I_IntInit(0)     if ($type->is('T_Int');
    return I_LongInit(0) if ($type->is('T_Long');
    die "unknown type $type (get_default_init)";
}


1;
