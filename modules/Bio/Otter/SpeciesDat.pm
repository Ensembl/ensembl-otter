
package Bio::Otter::SpeciesDat;

# Read and maintain the hash from 'species.dat'.
# (Inherited by Bio::Otter::MFetcher)
#
# Author: lg4

use strict;
use warnings;


sub get_dataset_param {
    my ($self, $dataset_name, $param_name) = @_;

    my $all_species = $self->dataset_hash;
    my $subhash = $all_species->{$dataset_name} || die "Unknown Dataset '$dataset_name'";
    return $subhash->{$param_name};
}

sub dataset_hash { # used by scripts/apache/get_datasets only
    my ($self) = @_;

    unless ($self->{'_species_dat_hash'}) {
        $self->load_species_dat_file;
    }
    return $self->{'_species_dat_hash'};
}

sub species_dat_filename {
    my( $self, $filename ) = @_;

    if($filename) {
        $self->{'_species_dat_filename'} = $filename;
    }
    return $self->{'_species_dat_filename'};
}

sub load_species_dat_file {
    my ($self) = @_;

    my $filename = $self->species_dat_filename();

    open my $dat, '<', $filename or die "Can't read species file '$filename' : $!";

    my $cursect = undef;
    my $defhash = {};
    my $curhash = undef;
    my $sp = $self->{'_species_dat_hash'} = {};

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

    return;
}

sub keep_only_datasets {
    my ($self, $allowed_hash) = @_;

    my $sp = $self->dataset_hash;

    foreach my $dataset_name (keys %$sp) {
        warn sprintf "Dataset %s is %sallowed\n"
            , $dataset_name, $allowed_hash->{$dataset_name} ? '' : 'not ';
        delete $sp->{$dataset_name} unless $allowed_hash->{$dataset_name};
    }

    return;
}

sub remove_restricted_datasets {
    my ($self, $allowed_hash) = @_;
    
    my $sp = $self->dataset_hash;

    foreach my $dataset_name (keys %$sp) {
        next unless $sp->{$dataset_name}{'RESTRICTED'};
        delete $sp->{$dataset_name} unless $allowed_hash->{$dataset_name};
    }

    return;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

