package ADT;
use strict;
use warnings;
use feature qw(say);

use overload
	'""' => sub {
		my $self = shift;
		my $fields_string = join(", ", map { $_ . ": "  . $self->{$_} } $self->fields_order());
		return $self->{_tag} . "(" . $fields_string . ")";
	};


our %type_info;

sub new {
	my ($class, $base_type, $tag, @args) = @_;
	my %map = (
		_tag => $tag, _base_type => $base_type
	);
	my @param_names = $type_info{$tag}->{param_names}->@*;
	while (my ($i, $arg) = each @args) {
		$map{$param_names[$i]} = $arg;
	}
	return bless \%map, $class;
}

sub is {
	my ($self, $tag) = @_;
	return $self->{_tag} eq $tag || $self->{_base_type} eq $tag;
}

sub is_one_of {
	my ($self, @tags) = @_;
	return grep { $self->is($_) } @tags;
}

sub index_of_in {
	my ($self, @tags) = @_;
	while (my ($i, $tag) = each @tags) {
		return $i if $self->is($tag);
	}	
	return -1;
}

sub match {
	my ($self, $tag) = @_;
	if ($self->{_tag} eq $tag) {
		my @vals = $self->values_in_order();
		return @vals ? @vals : (1);
	} else {
		return ();
	}
}

sub values_in_order {
	my $self = shift;
	return map { $self->{$_} } $self->fields_order();
}

sub fields_order {
	my $self = shift;
	return $type_info{$self->{_tag}}->{param_names}->@*;
}

1;
