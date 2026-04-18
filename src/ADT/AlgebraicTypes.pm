package ADT::AlgebraicTypes;
use strict;
use warnings;
use feature qw(isa);

use Cwd qw(abs_path);

use ADT::ParseASDL;

require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = 'is_ADT';
our @EXPORT_OK;
our %EXPORT_TAGS;

BEGIN {
	#$Exporter::Verbose = 1;
	open(my $fh, "<", $main::src_dir . "/types.asdl") or die $!;
	my @lines = <$fh>;
	my %constructors = ADT::ParseASDL::parse_types(@lines);
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

1;
