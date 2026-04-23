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

sub add_to_symtable {
	my ($pkg_name, %constructors) = @_;
	no strict 'refs';
	while (my ($name, $sub) = each %constructors) {
		*{"${pkg_name}::${name}"} = $sub
	}
}

BEGIN {
	#$Exporter::Verbose = 1;
	open(my $fh, "<", $main::src_dir . "/types.asdl") or die $!;
	my @asdl_lines = <$fh>;
	my %constructors = ADT::ParseASDL::parse_types(@asdl_lines);
	add_to_symtable('ADT::AlgebraicTypes', %constructors);
	for my $constr_name (keys %constructors) {
		if ($constr_name =~ /^([A-Z][A-Za-z0-9]*)_.*/) {
			push @EXPORT_OK, $constr_name;
			push $EXPORT_TAGS{$1}->@*, $constr_name;
		} else {
			push @EXPORT, $constr_name;
		}
	}
}

sub local_types {
	my ($pkg_name, @asdl_lines) = @_;
	my %constructors = ADT::ParseASDL::parse_types(@asdl_lines);
	add_to_symtable($pkg_name, %constructors);
}

sub is_ADT {
	my ($adt, @tags) = @_;
	return $adt isa ADT::ADT && $adt->is(@tags);
}

1;
