package ADTSupport;
use strict;
use warnings;
use feature qw(say);

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

my %constructors_info;

sub get_ordered_fields {
	my $tag = shift;
	return $constructors_info{$tag}{param_names}->@*;
}

sub declare {
	my ($base, $constructors) = @_;
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
			my %adt = (tag => $constr_tag);
			for my $arg (@_) {
				die "bad value in constructor $constr_tag: $arg" unless check_type($arg, shift(@param_types));
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
	return 0 unless defined $type;
	return 1;
}

sub match {
	my ($adt, $matched_tag) = @_;
	if ($adt->{tag} eq $matched_tag) {
		return map { $adt->{$_} } get_ordered_fields($matched_tag);
	} else {
		return ();
	}
}



1;
