package ADT::ParseASDL;
use strict;
use warnings;
use feature qw(say isa);

use ADT::ADT;

#require Exporter;
#our @ISA = qw(Exporter);
#our @EXPORT = qw(declare);
#
#BEGIN {
#	#	$Exporter::Verbose = 1;
#}
#sub import {
#	say "import asdl";
#	ADT::ParseASDL->export_to_level(2, @_);
#}


my $type_name_re = qr/[A-Z]\w*|int|string|bool/;
my $param_name_re = qr/\w+/;

sub declare {
	my @asdl_tokens = map { length ? $_ : () } split(/[\s)(,]+/, shift);
	my $base_type = valid_name(shift @asdl_tokens, $type_name_re);
	die "bad syntax: no =" if (shift(@asdl_tokens) ne '=');

	my @constructors = ([]);
	for my $token (@asdl_tokens) {
		if ($token eq '|') {
			push @constructors, [];
		} else {
			push $constructors[-1]->@*, $token;
		}
	}
	
	my %constructor_subs;
	for my $constructor (@constructors) {
		my $constr_tag = valid_name(shift @$constructor, $type_name_re);
		push($ADT::type_info{$base_type}->{constructors}->@*, $constr_tag);

		my (@param_types, @param_names);
		while (my ($i, $token) = each @$constructor) {
			if ($i++ % 2 == 0) {
				push(@param_types, to_type($token));
			} else {
				push(@param_names, valid_name($token, $param_name_re));
			}
		}
		die "$constr_tag: nums of param names/types not equal" if (@param_types != @param_names);
		$ADT::constructor_info{$constr_tag} = {
			param_types => \@param_types,
			param_names => \@param_names,
		};

		my $constructor_sub = sub {
			validate_args(\@_, \@param_types);
			return ADT->new($base_type, $constr_tag, @_);
		};
		$constructor_subs{$constr_tag} = $constructor_sub;
	}
	return %constructor_subs;
}

sub valid_name {
	my ($name, $re) = @_; 
	return ($name =~ /^$re$/) ? $name : die "bad name: $name";
}

sub to_type {
	my ($name, $is_opt, $is_arr) = $_[0] =~ /^($type_name_re)(\?)?(\*)?$/;
	return (defined $name && !(length($is_opt) && length($is_arr))) 
		? { full_name => $_[0], name => $name, optional => length $is_opt, array =>  length $is_arr }
		: die "bad type: " . $_[0];
}	

sub validate_args {
	my ($args, $types) = @_;
	die(sprintf("num of args/types mismatch: %d / %d", scalar(@$args), scalar(@$types))) if (@$args != @$types);

	for my $i (0..$#$args) {
		my ($arg, $type) = ($args->[$i], $types->[$i]);
		if (!defined $arg) {
			die("undef arg for type " . $type->{full_name}) unless ($type->{optional});
		} elsif ($type->{array}) {
			die("non-array $arg for type " . $type->{full_name}) unless (ref($arg) eq 'ARRAY');
			validate_arg($_, $type->{name}) for $arg->@*;
		} else {
			validate_arg($arg, $type->{name});
		}
	}
}

sub validate_arg {
	my ($arg, $type_name) = @_;
	if ($type_name =~ /^[A-Z]/) {
		die "$arg not ADT"	 unless ($arg isa 'ADT');
		die "$arg not $type_name" unless ($arg->{_base_type} eq $type_name);
	} elsif ($type_name eq 'int') {
		die "$arg not int" if ($arg !~ /^-?\d+$/);
	} 
	# bool a string asi cokoliv	
}

1;


