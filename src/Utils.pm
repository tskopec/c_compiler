package Utils;
use strict;
use warnings FATAL => 'all';
use feature qw(state isa say current_sub);

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(print_tree labels align_to string_to_int_consts escape_str unescape_str);

use feature qw(state);
use ADT::ADT;
use ADT::AlgebraicTypes qw(:C);

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
sub string_to_int_consts {
	my $string = shift;
	my $width = 4;
	my @result;
	while ($string =~ s/^(.{1,$width})//s) {
		my @chars = split //, $1;
		if (@chars == $width) {
			my $int = ord($chars[0]);
			$int |= ord($chars[$_]) << (8 * $_) for (1..$#chars);
			push @result, C_ConstInt($int);
		} else {
			push(@result, C_ConstChar(ord($_))) for @chars;
		}
	}
	return @result;
}

sub escape_str {
	state %seqs = (
		qr/\x{07}/ => '\x07', qr/\x{08}/ => '\b', qr/\x{0c}/ => '\f', qr/\x{0a}/ => '\n', qr/\x{09}/ => '\t',
		qr/\x{0b}/ => '\x0b', qr/\x{0d}/ => '\r', qr/'/ => '\'', qr/"/ => '\"'
	);
	return replace_all(shift =~ s/\\/\\\\/gr, \%seqs);
}

sub unescape_str {
	state %seqs = (
		qr/\Q\a/ => "\a", qr/\Q\b/ => "\b", qr/\Q\f/ => "\f", qr/\Q\n/ => "\n", qr/\Q\t/ => "\t", qr/\Q\v/ => '', 		# perl zrusil \v https://prog21.dadgum.com/76.html
		qr/\Q\r/ => "\r", qr/\Q\'/ => "'", qr/\Q\"/ => "\"", qr/\Q\\/ => "\\", qr/\Q\?/ => "?",
	);
	return replace_all(shift, \%seqs);
}

sub replace_all {
	my ($str, $map) = @_;
	while (my ($pattern, $replace) = each %$map) {
		$str =~ s/$pattern/$replace/g;
	}
	return $str;
}

1;