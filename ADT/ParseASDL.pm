package ADT::ParseASDL;
use strict;
use warnings;
use feature qw(say isa);

use lib "./ADT";
use ADT;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(declare);

BEGIN {
	#	$Exporter::Verbose = 1;
}
sub import {
	ADT::ParseASDL->export_to_level(2, @_);
}


sub declare {
	my @asdl_tokens = split(/[\s)(,]+/, trim(shift));
	my $base_type = valid_name(shift @asdl_tokens);
	die "bad syntax: no '='" if (shift(@asdl_tokens) ne '=');

	my @variants = ([]);
	for my $token (@asdl_tokens) {
		next if ($token eq '');
		if ($token eq '|') {
			push @variants, [];
		} else {
			push $variants[-1]->@*, $token;
		}
	}
	
	for my $variant (@variants) {
		my $constr_tag = valid_name(shift @$variant);
		push($ADT::type_info{$base_type}->{variants}->@*, $constr_tag);

		my (@param_types, @param_names);
		while (my ($i, $token) = each @$variant) {
			if ($i++ % 2 == 0) {
				push(@param_types, to_type($token));
			} else {
				push(@param_names, valid_name($token));
			}
		}
		die "$constr_tag: nums of param names/types not equal" if (@param_types != @param_names);
		$ADT::constructor_info{$constr_tag} = {
			param_names => \@param_names,
			param_types => \@param_types,
		};

		my $constructor_sub = sub {
			validate_args(\@_, \@param_types);
			return ADT->new($base_type, $constr_tag, @_);
		};
		{ no strict 'refs'; *{$constr_tag} = $constructor_sub; }	
		push(@EXPORT, $constr_tag);
	}
}

sub valid_name {
	die("bad name: " . $_[0]) if (!defined $_[0] || $_[0] !~ /^\w+$/);
	return $_[0];
}

sub to_type {
	my ($name, $is_opt, $is_arr) = $_[0] =~ /^(\w+)(\?)?(\*)?$/;
	die("bad type: " . $_[0]) if (!defined $name || ($is_opt && $is_arr));
	return { full_name => $_[0], name => $name, optional => !!$is_opt, array => !!$is_arr };
}	

sub validate_args {
	my ($args, $types) = @_;
	die "num of args/types mismatch: @$args / @$types" if (@$args != @$types);
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
	if ($type_name eq 'Integer') {
		die "$arg not int" if ($arg !~ /^\d+$/);
	} elsif ($type_name eq 'String') {
		;
	} elsif ($type_name eq 'Bool') {
		die "$arg not bool" if ($arg =~ /[^01]/);
	} else {
		die "$arg not ADT"	 unless ($arg isa 'ADT');
		die "$arg not $type_name" unless ($arg->is($type_name));
	}	
}

sub trim {
	return $_[0] =~ s/^\s+|\s+$//rg;
}

1;


