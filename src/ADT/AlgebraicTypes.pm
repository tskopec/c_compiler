package ADT::AlgebraicTypes;
use strict;
use warnings;
use feature qw(say isa current_sub state);

use Cwd qw(abs_path);

use ADT::ADT;
use ADT::ParseASDL;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw(print_tree is_ADT);
our @EXPORT_OK;
our %EXPORT_TAGS;

BEGIN {
	#$Exporter::Verbose = 1;
	open(my $fh, "<", $main::src_dir . "/types.asdl") or die $!;
	my %constructors = ADT::ParseASDL::parse_file($fh);
	while (my ($name, $sub) = each %constructors) {
		{ no strict 'refs'; *{$name} = $sub } 
		if ($name =~ /^([A-Z][A-Za-z0-9]*)_.*/) {
			push @EXPORT_OK, $name;
			push $EXPORT_TAGS{$1}->@*, $name;
		} else {
			push @EXPORT, $name;
		}
	}
}

sub is_ADT {
	my ($adt, @tags) = @_;
	return $adt isa ADT::ADT && $adt->is(@tags);
}

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
		} else {
			say(($tab x $indent) . "$key: " . (defined($node) ? qq("$node") : 'undef'));
		}
	};
	$print_node->("root", shift(), 0);
	print "\n";
}

1;
