package ADTSupport;
use strict;
use warnings;
use feature qw(say isa);

use ADT;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(declare match);

BEGIN {
	#	$Exporter::Verbose = 1;
}
sub import {
	ADTSupport->export_to_level(2, @_);
}

our %constructors_info;

sub declare {
	my ($base_type, $constructors) = @_;
	while (@$constructors) {
		my $constr_tag = shift @$constructors;
		my (@param_names, @param_types);
		if (ref($constructors->[0]) eq 'ARRAY') {
			my $params = shift @$constructors;
			while (my ($i, $p) = each ($params->@*)) {
				($i % 2 == 0) ? push(@param_names, $p) : push(@param_types, $p);
			}	
		}
		$constructors_info{$constr_tag} = { param_names => [@param_names], param_types => [@param_types] };

		my $constructor_sub = sub {
			my %adt = (_base_type => $base_type, _tag => $constr_tag);
			for my $arg (@_) {
				check_type($arg, shift(@param_types));
				$adt{shift @param_names} = $arg;
			}
			return ADT->new(%adt);
		};
		{ no strict 'refs'; *{$constr_tag} = $constructor_sub; }	
		push(@EXPORT, $constr_tag);
	}
	ADTSupport->export_to_level(2, 'ADTSupport');
}

sub check_type {
	my ($arg, $type) = @_;
	die "undef type for arg $arg" unless defined $type;

	if (substr($type, -1) ne '?' && !defined $arg) {
		die "undef arg for non-optional type $type";
	} elsif (substr($type, -1) eq '*') {
		die "$arg not an array" if (ref($arg) ne 'ARRAY');
		my $elem_type = substr($type, 0, -1);
		check_type($_, $elem_type) for $arg->@*;
	}

	if (starts_with($type, "int")) {
		die "$arg not int" if ($arg !~ /^\d+$/);
	} elsif (starts_with($type, "string")) {
		die "invalid string $arg" if ($arg !~ /^\w*$/);
	} elsif (starts_with($type, 'bool')) {
		die "$arg not bool" if ($arg != 0 && $arg != 1);
	} else {
		die "$arg not ADT" unless ($arg isa 'ADT');
		unless (grep { $arg->is($_) } split(/\|/, $type)) {
			die "$arg not $type";
		}
	}	
}

sub starts_with {
	my ($str, $prefix) = @_;
	return not rindex $str, $prefix, 0;
}

sub match {
	my ($adt, $tag) = @_;
	die "not ADT $adt" unless ($adt isa 'ADT');
	if ($adt->{_tag} eq $tag) {
		return $adt->values_in_order() || (1);
	} else {
		return ();
	}
}



1;
