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
our %constructor_info;

sub new {
	my ($class, $base_type, $tag, @args) = @_;
	my %map = (
		_tag => $tag, _base_type => $base_type
	);
	my @param_names = $constructor_info{$tag}->{param_names}->@*;
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
	my ($self, $cases) = @_;
	if (!exists $cases->{default} && grep { !exists $cases->{$_} } $type_info{$self->{_base_type}}->{variants}->@*) {
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
