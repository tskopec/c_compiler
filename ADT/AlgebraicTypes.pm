package ADT::AlgebraicTypes;
use strict;
use warnings;
use feature qw(say isa current_sub state);

use ADT::ADT;
use ADT::ParseASDL;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(print_tree);
our @EXPORT_OK;
our %EXPORT_TAGS;

BEGIN {
	open(my $fh, "<", "./types.asdl") or die $!;
	my %constructors = ADT::ParseASDL::parse_file($fh);
	while (my ($name, $sub) = each %constructors) {
		{ no strict 'refs'; *{$name} = $sub } 
		push @EXPORT_OK, $name;
		if ($name =~ /^([A-Z][A-Za-z0-9]*)_.*/) {
			push $EXPORT_TAGS{$1}->@*, $name;
		}
	}
}


sub print_tree {
	state $tab = "  ";
	my $print_node = sub {
		my ($node, $indent) = @_;
		if ($node isa ADT::ADT) {
			say(($tab x $indent) . $node->{_tag});
			__SUB__->($_, $indent + 1) for $node->values_in_order();
		} elsif (ref($node) eq 'ARRAY') {
			say(($tab x $indent) . 'array:');
			__SUB__->($_, $indent + 1) for $node->@*;
		} else {
			say(($tab x $indent) . ($node // 'undef'));
		}
	};
	$print_node->(shift(), 0);
	print "\n";
}

1;
