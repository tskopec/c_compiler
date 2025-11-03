package ADT::ParseASDL;
use strict;
use warnings;
use feature qw(say isa);

use List::MoreUtils qw(part);

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
	my @asdl_tokens = split(/[\s)(]+/, trim(shift));
	my $base_type = shift @asdl_tokens // die "no tokens";
	my @variants;

	for my $token (@asdl_tokens) {
		if ($token =~ /[=|]/) {
			push @variants, [];
		} else {
			push $variants[-1]->@*, $token;
		}
	}
	
	for my $variant (@variants) {
		my $constr_tag = shift @$variant // die "$base_type: no tag";
		push($ADT::type_info{$base_type}->{variants}->@*, $constr_tag);

		my $i = 0;
		my ($param_types, $param_names) = part { $i++ % 2 } @$variant;
		$param_types //= [];
		$param_names //= [];
		die "$constr_tag: nums of param names/types not equal" unless (@$param_types == @$param_names);
		$ADT::constructor_info{$constr_tag} = {
			param_names => $param_names,
			param_types => $param_types,
		};

		my $constructor_sub = sub {
			validate_args(\@_, $param_types);
			return ADT->new($base_type, $constr_tag, @_);
		};
		{ no strict 'refs'; *{$constr_tag} = $constructor_sub; }	
		push(@EXPORT, $constr_tag);
	}
}

sub validate_args {
	my ($args, $types) = @_;
	die "args/types mismatch: @$args / @$types" if (@$args != @$types);
	for my $i (0..$#$args) {
		validate_arg($args->[$i], $types->[$i]);
	}
}

sub validate_arg {
	my ($arg, $type) = @_;
	die "undef type for arg $arg" unless defined $type;

	if (!defined $arg) {
		substr($type, -1) eq '?' ? return : die "undef arg for non-optional type $type";
	}
	if (substr($type, -1) eq '*') {
		die "$arg not an array" if (ref($arg) ne 'ARRAY');
		my $elem_type = substr($type, 0, -1);
		validate_arg($_, $elem_type) for $arg->@*;
	}
	if ($type =~ /^Integer[?*]?$/) {
		die "$arg not int" if ($arg !~ /^\d+$/);
	} elsif ($type =~ /^String[?*]?$/) {
		;
	} elsif ($type =~ /^Bool[?*]?$/) {
		die "$arg not bool" if ($arg != 0 && $arg != 1);
	} else {
		die "$arg not ADT" unless ($arg isa 'ADT');
		die "$arg not $type" unless ($arg->is($type));
	}	
}

sub trim {
	return $_[0] =~ s/^\s+|\s+$//rg;
}

1;


