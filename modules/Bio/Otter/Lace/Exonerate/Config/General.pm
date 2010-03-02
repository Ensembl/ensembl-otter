
## no critic(Modules::RequireFilenameMatchesPackage)

package Bio::EnsEMBL::Analysis::Config::General;

use strict;
use warnings;

#### Stop anyone else loading their own Config::General
$INC{q(Bio/EnsEMBL/Analysis/Config/General.pm)}++;

sub import {

    my ($callpack) = caller(0); # Name of the calling package
    my $pack = shift; # Need to move package off @_

    # had to put this inline here
    my %Config = (

                  DATA_DIR => '/data/blastdb/Finished',
                  LIB_DIR  => '/software/anacode/lib',
                  BIN_DIR  => '/software/anacode/bin',


                  # temporary working space (e.g. /tmp)
                  ANALYSIS_WORK_DIR => '/tmp',

                  ANALYSIS_REPEAT_MASKING => ['RepeatMasker','trf'],

                  SOFT_MASKING => 0,
                  );

    # Get list of variables supplied, or else all
    my @vars = @_ ? @_ : keys(%Config);
    return unless @vars;

    # Predeclare global variables in calling package
    {
        ## no critic(BuiltinFunctions::ProhibitStringyEval)
        eval "package $callpack; use vars qw("
            . join(' ', map { '$'.$_ } @vars) . ")";
        die $@ if $@;
    }


    foreach (@vars) {
        if (defined $Config{$_}) {
            ## no critic(TestingAndDebugging::ProhibitNoStrict)
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
}

1;
