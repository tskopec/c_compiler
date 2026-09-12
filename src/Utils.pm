package Utils;
use strict;
use warnings FATAL => 'all';
use feature qw(state isa say current_sub);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(print_tree labels align_to string_to_ints);

use ADT::ADT;

our %color = (	# https://ss64.com/nt/syntax-ansi.html
	r => "\033[31;1m",
	g => "\033[32;1m",
	y => "\033[33;1m",
	b => "\033[34;1m",
	off => "\033[0m"
);

sub print_tree {
	state $tab = "    ";
	my $print_node = sub {
		my ($key, $node, $indent) = @_;
		if ($node isa ADT::ADT) {
			say(($tab x $indent) . "$key: " . $node->{':tag'});
			__SUB__->($_, $node->{$_}, $indent + 1) for $node->keys_in_order();
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
				__SUB__->($_, $node->{$_}, $indent + 1) for (sort keys %$node);
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

# round val to next multiple of alignment
sub align_to {
	my ($val, $alignment) = @_;
	return $alignment * int(($val + $alignment - 1) / $alignment);
}

#  string="abcdefg", width=4 -> 1684234849,101,102,103 (little-endian)
sub string_to_ints {
	my ($string, $width) = (shift, shift || 4);
	my @result;
	while ($string =~ s/^(.{1,$width})//) {
		my @chars = split //, $1;
		if (@chars == $width) {
			push @result, ord($chars[0]);
			$result[-1] |= ord($chars[$_]) << (8 * $_) for (1..$#chars);
		} else {
			push(@result, ord($_)) for @chars;
		}
	}
	return @result;
}



1;