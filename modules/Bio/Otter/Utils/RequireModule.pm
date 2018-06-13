=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

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
