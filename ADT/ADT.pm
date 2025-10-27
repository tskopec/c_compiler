package ADT;

use feature qw(say);

use ADTSupport;
use overload
	'""' => sub {
		my $this = shift;
		my $fields_string = join(", ", map { $_ . ": "  . $this->{$_} } ADTSupport::get_ordered_fields($this->{tag}));
		return $this->{tag} . "(" . $fields_string . ")";
	};

sub new {
	my ($class, %args) = @_;
	return bless \%args, $class;
}


1;
