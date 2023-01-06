=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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


## no critic (Modules::RequireFilenameMatchesPackage)

package Bio::EnsEMBL::Analysis::Config::Blast;

use strict;
use warnings;

#### Stop anyone else loading their own Config::Blast
$INC{q(Bio/EnsEMBL/Analysis/Config/Blast.pm)}++;

sub import {
    my ($pack, @vars) = @_;

    my ($callpack) = caller(0); # Name of the calling package

    # had to put this inline here.
    my %Config = (
                  DB_CONFIG => [{name =>'empty'}],
                  UNKNOWN_ERROR_STRING => 'WHAT',
                  );


    # Get list of variables supplied, or else all
    @vars = keys %Config unless @vars;
    return unless @vars;

    # Predeclare global variables in calling package
    {
        ## no critic (BuiltinFunctions::ProhibitStringyEval,Anacode::ProhibitEval)
        eval "package $callpack; use vars qw("
            . join(' ', map { '$'.$_ } @vars) . ")";
        die $@ if $@;
    }


    foreach (@vars) {
        if (defined $Config{ $_ }) {
            ## no critic (TestingAndDebugging::ProhibitNoStrict)
            no strict 'refs';
            # Exporter does a similar job to the following
            # statement, but for function names, not
            # scalar variables:
            *{"${callpack}::$_"} = \$Config{ $_ };
        } else {
            die "Error: Config: $_ not known (See Bio::Otter::Lace::Blast)\n";
        }
    }

    return;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

