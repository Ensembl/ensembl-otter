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

package Bio::EnsEMBL::Analysis::Config::General;

use strict;
use warnings;

#### Stop anyone else loading their own Config::General
$INC{q(Bio/EnsEMBL/Analysis/Config/General.pm)}++;

sub import {
    my ($pack, @vars) = @_;

    my ($callpack) = caller(0); # Name of the calling package

    # had to put this inline here
    my %Config = (

                  # These are required to be set by B:E:A:Runnable,
                  # but we don't want them to be used.
                  DATA_DIR => '/dev/null',
                  LIB_DIR  => '/dev/null',
                  BIN_DIR  => '/dev/null',


                  # temporary working space (e.g. /tmp)
                  ANALYSIS_WORK_DIR => '/tmp',

                  ANALYSIS_REPEAT_MASKING => ['RepeatMasker','trf'],

                  SOFT_MASKING => 0,
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
        if (defined $Config{$_}) {
            ## no critic (TestingAndDebugging::ProhibitNoStrict)
            no strict 'refs';

            # Exporter does a similar job to the following
            # statement, but for function names, not
            # scalar variables:
            *{"${callpack}::$_"} = \$Config{$_};
        }
        else {
            die "Error: Config: $_ not known (See Bio::Otter::Lace::Blast)\n";
        }
    }

    return;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

