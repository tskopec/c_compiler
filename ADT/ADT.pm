package ADT::ADT;
use strict;
use warnings;
use feature qw(isa);

use overload
	'""' => sub {
		my $self = shift;
		my $fields_string = join(", ", map { $_ . ": "  . $self->{$_} } $self->fields_order());
		return $self->{_tag} . "(" . $fields_string . ")";
	};


our %variants_info;
our %constructor_info;

sub new {
	my ($class, $base_type, $tag, @args) = @_;
	validate_args(\@args, $constructor_info{$tag}->{param_types});

	my %map = (
		_tag => $tag, _base_type => $base_type
	);
	my @param_names = $constructor_info{$tag}->{param_names}->@*;
	while (my ($i, $arg) = each @args) {
		$map{$param_names[$i]} = $arg;
	}
	return bless \%map, $class;
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
		die "$arg not ADT"	 unless ($arg isa 'ADT::ADT');
		die "$arg not $type_name" unless ($arg->{_base_type} eq $type_name);
	} elsif ($type_name eq 'int') {
		die "$arg not int" if ($arg !~ /^-?\d+$/);
	} 
	# bool a string asi cokoliv	
}


sub is {
	my ($self, @tags) = @_;
	return $self->index_of_in(@tags) != -1;
}

sub index_of_in {
	my ($self, @tags) = @_;
	while (my ($i, $tag) = each @tags) {
		return $i if ($self->{_tag} eq $tag || $self->{_base_type} eq $tag);
	}	
	return -1;
}

sub match {
	my ($self, $cases) = @_;
	if (!exists $cases->{default} && grep { !exists $cases->{$_} } $variants_info{$self->{_base_type}}->{constructors}->@*) {
		die "cases for type " . $self->{_base_type} . " not exhausted:\n" . (join "\n", keys %$cases);
	}
	my $sub = $cases->{$self->{_tag}} // $cases->{default} ;
	$sub->($self->values_in_order());
}

sub values_in_order {
	my $self = shift;
	return map { $self->{$_} } $self->fields_order();
}

sub fields_order {
	my $self = shift;
	return $constructor_info{$self->{_tag}}->{param_names}->@*;
}

1;
