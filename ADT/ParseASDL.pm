package ADT::ParseASDL;
use strict;
use warnings;

use ADT::ADT;


my $type_name_re = qr/[A-Z]\w*|int|string|bool/;
my $param_name_re = qr/\w+/;

sub parse_file {
	my $fh = shift;
	my @constructors;
	my $current_declaration;
	while (<$fh>) {
		next if /^#|^\s+$/;
		if (/=/ && length $current_declaration) {
			push(@constructors, parse_declaration($current_declaration));
			$current_declaration = "";
		} 
		$current_declaration .= $_;
	}
	push(@constructors, parse_declaration($current_declaration));
	return @constructors;
}

sub parse_declaration {
	my @asdl_tokens = map { length ? $_ : () } split(/[\s)(,]+/, shift);
	my $base_type = valid_name(shift @asdl_tokens, $type_name_re);
	die "bad syntax: no =" if (shift(@asdl_tokens) ne '=');

	my @constructors = ([]);
	for my $token (@asdl_tokens) {
		if ($token eq '|') {
			push @constructors, [];
		} else {
			push $constructors[-1]->@*, $token;
		}
	}
	
	my %constr_subs;
	for my $constr (@constructors) {
		my $constr_tag = valid_name(shift @$constr, $type_name_re);

		my (@param_types, @param_names);
		while (my ($i, $token) = each @$constr) {
			if ($i++ % 2 == 0) {
				push(@param_types, to_type($token));
			} else {
				push(@param_names, valid_name($token, $param_name_re));
			}
		}
		die "$constr_tag: nums of param names/types not equal" if (@param_types != @param_names);
		push($ADT::ADT::type_info{$base_type}->{constructors}->@*, $constr_tag);
		$ADT::ADT::constructor_info{$constr_tag} = {
			param_types => \@param_types,
			param_names => \@param_names,
		};

		my $constr_sub = sub {
			return ADT::ADT->new($base_type, $constr_tag, @_);
		};
		$constr_subs{$constr_tag} = $constr_sub;
	}
	return %constr_subs;
}

sub valid_name {
	my ($name, $re) = @_; 
	return ($name =~ /^$re$/) ? $name : die "bad name: $name";
}

sub to_type {
	my ($name, $is_opt, $is_arr) = $_[0] =~ /^($type_name_re)(\?)?(\*)?$/;
	return (defined $name && !(length($is_opt) && length($is_arr))) 
		? { full_name => $_[0], name => $name, optional => length $is_opt, array =>  length $is_arr }
		: die "bad type: " . $_[0];
}	


1;


