package ADT;

use feature qw(say);

use ADTSupport;
use overload
	'""' => sub {
		my $self = shift;
		my $fields_string = join(", ", map { $_ . ": "  . $self->{$_} } %{$self->get_info()}{param_names}->@*);
		return $self->{_tag} . "(" . $fields_string . ")";
	};

sub new {
	my ($class, %args) = @_;
	return bless \%args, $class;
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

sub get_info {
	my $self = shift;
	return $ADTSupport::constructors_info{$self->{_tag}};
}

sub values_in_order {
	my $self = shift;
	return map { $self->{$_} } %{$self->get_info()}{param_names}->@*;
}

1;
