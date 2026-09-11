package Utils;
use strict;
use warnings FATAL => 'all';
use feature qw(state isa say current_sub);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(print_tree labels align_to);

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

# TODO nejak lip
sub chars_to_ints {
	my ($string, $width) = @_;
	my @chars = split //, $string;
	my @result;

	for (my $i = 0; $i < @chars; $i += $width) {
		if (@chars - $i > $width) {
			my $n = 0;
			for (my $j = 0; $j < $width; $j++) {
				$n |= (ord($chars[$i + $j]) << (8 * $j));
			}
			push @result, $n;
		} else {
			for (my $j = $i; $j < @chars; $j++) {
				push @result, ord($chars[$j]);
			}
		}
	}
	return @result;
}



1;