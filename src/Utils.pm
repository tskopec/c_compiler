package Utils;
use strict;
use warnings FATAL => 'all';
use feature qw(state isa say current_sub);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(print_tree labels);

use ADT::ADT;

sub print_tree {
	state $tab = "  ";
	my $print_node = sub {
		my ($key, $node, $indent) = @_;
		if ($node isa ADT::ADT) {
			say(($tab x $indent) . "$key: " . $node->{':tag'});
			__SUB__->($_, $node->{$_}, $indent + 1) for $node->fields_order();
		} elsif (ref($node) eq 'ARRAY') {
			if (@$node) {
				say(($tab x $indent) . "$key: [");
				__SUB__->($_, $node->[$_], $indent + 1) for (0..$#$node);
				say(($tab x $indent) . "]");
			} else {
				say(($tab x $indent) . "$key: []");
			}
		} elsif (ref($node) eq 'HASH') {
			if (keys %$node) {
				say(($tab x $indent) . "$key: {");
				__SUB__->($_, $node->{$_}, $indent + 1) for (keys %$node);
				say(($tab x $indent) . "}");
			} else {
				say(($tab x $indent) . "$key: {}");
			}
		} else {
			say(($tab x $indent) . "$key: " . (defined($node) ? qq("$node") : 'undef'));
		}
	};
	$print_node->("root", shift(), 0);
	print "\n";
}


sub labels {
	my @res = map { "_${_}_" . $::global_counter } @_;
	$::global_counter++;
	return @res;
}

1;