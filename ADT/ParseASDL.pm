package ParseASDL;
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
	ParseASDL->export_to_level(2, @_);
}


sub declare {
	my @words = split(/[\s)(]+/, trim(shift));
	my $base_type = shift @words;
	my @variants;

	for my $word (@words) {
		if ($word =~ /[=|]/) {
			push @variants, [];
		} else {
			push $variants[-1]->@*, $word;
		}
	}
	
	for my $variant (@variants) {
		my $constr_tag = shift @$variant;
		my $i = 0;
		my ($param_types, $param_names) = part { $i++ % 2 } @$variant;
		die "nums of param names/types not equal" unless (@$param_types == @$param_names);
		$ADT::type_info{$constr_tag} = {
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

	if (!ends_with($type, '?') && !defined $arg) {
		die "undef arg for non-optional type $type";
	} elsif (ends_with($type, '*')) {
		die "$arg not an array" if (ref($arg) ne 'ARRAY');
		my $elem_type = substr($type, 0, -1);
		validate_arg($_, $elem_type) for $arg->@*;
	}

	if (starts_with($type, "Int")) {
		die "$arg not int" if ($arg !~ /^\d+$/);
	} elsif (starts_with($type, "String")) {
		die "invalid string $arg" if ($arg !~ /^\w*$/);
	} elsif (starts_with($type, 'Bool')) {
		die "$arg not bool" if ($arg != 0 && $arg != 1);
	} else {
		die "$arg not ADT" unless ($arg isa 'ADT');
		unless (grep { $arg->is($_) } split(/\|/, $type)) {
			die "$arg not $type";
		}
	}	
}

sub trim {
	return $_[0] =~ s/^\s+|\s+$//rg;
}

sub starts_with {
	my ($str, $prefix) = @_;
	return not rindex $str, $prefix, 0;
}

sub ends_with {
	my ($str, $suffix) = @_;
	return substr($str, -1) eq $suffix;
}

1;


