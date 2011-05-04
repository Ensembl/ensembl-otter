
package Bio::Otter::SpeciesDat;

# Read and maintain the hash from 'species.dat'.
#
# Author: lg4

use strict;
use warnings;

sub new {
    my ($pkg, $file) = @_;
    my $new = {
        _dataset_hash => _dataset_hash($file),
    };
    bless $new, $pkg;
    return $new;
}

sub dataset_hash { # used by scripts/apache/get_datasets only
    my ($self) = @_;

    return $self->{_dataset_hash};
}

sub _dataset_hash {
    my ($filename) = @_;

    open my $dat, '<', $filename or die "Can't read species file '$filename' : $!";

    my $cursect = undef;
    my $defhash = {};
    my $curhash = undef;
    my $sp = {};

    while (<$dat>) {
        next if /^\#/;
        next unless /\w+/;
        chomp;

        if (/\[(.*)\]/) {
            if (!defined($cursect) && $1 ne "defaults") {
                die "Error: first section in species.dat should be 'defaults'";
            }
            elsif ($1 eq "defaults") {
                warn "Got default section\n";
                $curhash = $defhash;
            }
            else {
                $curhash = {};
                foreach my $key (keys %$defhash) {
                    $key =~ tr/a-z/A-Z/;
                    $curhash->{$key} = $defhash->{$key};
                }
            }
            $cursect = $1;
            $sp->{$cursect} = $curhash;

        } elsif (/(\S+)\s+(\S+)/) {
            my $key   = uc $1;
            my $value =    $2;
            $curhash->{$key} = $value;
        }
    }

    close $dat or die "Error reading '$filename' : $!";

    # Have finished with defaults, so we can remove them.
    delete $sp->{'defaults'};

    return $sp;
}

sub otter_dba {
    my ($self, $dataset_name) = @_;

    die "No dataset name" unless $dataset_name;

    my $dataset = $self->dataset_hash->{$dataset_name};
    die "Unknown Dataset '$dataset_name'" unless $dataset;

    my $dbname = $dataset->{DBNAME};
    die "Failed opening otter database [No database name]" unless $dbname;

    require Bio::Vega::DBSQL::DBAdaptor;
    require Bio::EnsEMBL::DBSQL::DBAdaptor;

    my $odba;
    die "Failed opening otter database [$@]" unless eval {
        $odba = Bio::Vega::DBSQL::DBAdaptor->new(
            -host    => $dataset->{HOST},
            -port    => $dataset->{PORT},
            -user    => $dataset->{USER},
            -pass    => $dataset->{PASS},
            -dbname  => $dbname,
            -group   => 'otter',
            -species => $dataset_name,
            );
        1;
    };

    my $dna_dbname = $dataset->{DNA_DBNAME};
    if ($dna_dbname) {
        my $dnadb;
        die "Failed opening dna database [$@]" unless eval {
            $dnadb = Bio::EnsEMBL::DBSQL::DBAdaptor->new(
                -host    => $dataset->{DNA_HOST},
                -port    => $dataset->{DNA_PORT},
                -user    => $dataset->{DNA_USER},
                -pass    => $dataset->{DNA_PASS},
                -dbname  => $dna_dbname,
                -group   => 'dnadb',
                -species => $dataset_name,
                );
            1;
        };
        $odba->dnadb($dnadb);
    }

    return $odba;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

