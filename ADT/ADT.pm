package ADT::ADT;
use strict;
use warnings;
use feature qw(isa);

use overload
	'""' => sub {
		my $self = shift;
		my $fields_string = join(", ", map { $_ . ": "  . $self->{$_} } $self->fields_order());
		return $self->{':tag'} . "(" . $fields_string . ")";
	};


our %variants_info;
our %constr_info;

sub new {
	my ($class, $base_type, $tag, @args) = @_;
	my $info = $constr_info{$tag};
	if (@args != $info->{n_params}) {
		die(sprintf("num of args/types mismatch: %d / %d", scalar(@args), $info->{n_params}));
	}

	my $self = bless { ':tag' => $tag, ':base_type' => $base_type, }, $class;

	while (my ($i, $arg) = each @args) {
		my $param_name = $info->{params_order}[$i];
		$self->set($param_name, $arg);
	}
	return $self;
}


sub get {
	my ($self, $key) = @_;
	die "bad key $key" unless (exists $self->{$key});
	return $self->{$key};
}

sub set {
	my ($self, $key, $val) = @_;
	check_value($val, $constr_info{$self->{':tag'}}->{param_types}{$key});
	$self->{$key} = $val;
}

sub value_by_index {
	my ($self, $i) = @_;
	return $self->{$constr_info{$self->{':tag'}}->{params_order}->[$i]};
}


sub is {
	my ($self, @tags) = @_;
	return $self->index_of_in(@tags) != -1;
}

sub index_of_in {
	my ($self, @tags) = @_;
	while (my ($i, $tag) = each @tags) {
		return $i if ($self->{':tag'} eq $tag || $self->{':base_type'} eq $tag);
	}	
	return -1;
}

sub same_type_as {
    my ($self, $other) = @_;
    die "$other not ADT" unless ($other isa 'ADT::ADT');
    return $self->{':tag'} eq $other->{':tag'};
}

sub match {
	my ($self, $cases) = @_;
	if (!exists $cases->{default}) {
		my @missing = grep { !exists $cases->{$_} } $variants_info{$self->{':base_type'}}->@*;
		die "missing cases for type " . $self->{':base_type'} . ": @missing" if (@missing);
	}
	my $sub = $cases->{$self->{':tag'}} // $cases->{default};
	$sub->($self->values_in_order());
}


sub values_in_order {
	my ($self, $expected_type) = @_;
	if (defined $expected_type && !$self->is($expected_type)) {
		die "$self not $expected_type";
	}
	return map { $self->{$_} } $self->fields_order();
}

sub fields_order {
	my $self = shift;
	return $constr_info{$self->{':tag'}}->{params_order}->@*;
}


sub check_value {
	my ($value, $type) = @_;
	die "missing type for $value" if (!defined $type);
	if (!defined $value) {
		$type->{optional} ? return : die("undef val for type " . $type->{full_name});
	} elsif ($type->{array}) {
		die("non-array $value for type " . $type->{full_name}) unless (ref($value) eq 'ARRAY');
	}

	for my $val (ref($value) eq 'ARRAY' ? $value->@* : ($value)) {
		if ($type->{name} =~ /^[A-Z]/) {
			die("$val not ADT")				 unless ($val isa 'ADT::ADT');
			die("$val not " . $type->{name}) unless ($val->{':base_type'} eq $type->{name});
		} else {
			die("$val not primitive " . $type->{name}) unless (ref($val) eq "");
			if ($type->{name} eq 'int') {
				die "$val not int" if ($val !~ /^-?\d+$/);
			}
		} 
	}
}


1;
