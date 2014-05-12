package Bio::Otter::Utils::RequireModule;

use strict;
use warnings;

use Carp;

use base 'Exporter';
our @EXPORT_OK = qw( require_module );

# This is fairly simplistic and does not take account of multiple packages in one file.
# If we need that, see Class::C3::Componentised->ensure_class_loaded

# Not a method
#
sub require_module {
    my ($module, %option) = @_;

    ## no critic (BuiltinFunctions::ProhibitStringyEval,Anacode::ProhibitEval)
    if (eval "require $module") {
        return $module;
    } else {
        my $error = $@;
        croak "Couldn't load '$module': $error" unless $option{no_die} or $option{error_ref};
        ${$option{error_ref}} = $error if $option{error_ref};
        return;
    }
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
