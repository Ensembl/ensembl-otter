package Bio::Otter::SpeciesDat;

# Read and maintain the hash from 'species.dat'.
# (Inherited by Bio::Otter::MFetcher)
#
# Author: lg4

use strict;

sub species_dat_filename {
    my( $self, $filename ) = @_;

    if($filename) {
        $self->{'_species_dat_filename'} = $filename;
    }
    return $self->{'_species_dat_filename'};
}

sub make_sure_species_dat_file_loaded {
    my ($self) = @_;

    return if($self->{'_species_dat_hash'});

    $self->load_species_dat_file();
}
    
sub load_species_dat_file {
    my ($self) = @_;

    my $filename = $self->species_dat_filename();

    open my $dat, $filename or $self->error_exit("Can't read species file '$filename' : $!");

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
                $self->error_exit("Error: first section in species.dat should be 'defaults'");
            }
            elsif ($1 eq "defaults") {
	            $self->log("Got default section");
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
            $self->log("Reading entry $1 $2");
            $curhash->{$1} = $2;
        }
    }

    close $dat or $self->error_exit("Error reading '$filename' : $!");

    # Have finished with defaults, so we can remove them.
    delete $sp->{'defaults'};
}

sub keep_only_datasets {
    my ($self, $allowed_hash) = @_;

    my $sp = $self->{'_species_dat_hash'};

    foreach my $dataset_name (keys %$sp) {
        $self->log(sprintf("Dataset %s is %sallowed", $dataset_name, $allowed_hash->{$dataset_name} ? '' : 'not '));
        delete $sp->{$dataset_name} unless $allowed_hash->{$dataset_name};
    }
}

sub _species_hash { # used by nph-get_datasets only
    my ($self) = @_;

    $self->make_sure_species_dat_file_loaded();
    return $self->{'_species_dat_hash'};
}

sub get_dataset_param {
    my ($self, $dataset_name, $param_name) = @_;

    $self->make_sure_species_dat_file_loaded();

    my $subhash = $self->{'_species_dat_hash'}{$dataset_name} || $self->error_exit("Unknown Dataset '$dataset_name'");

    return $subhash->{$param_name};
}

sub log { # to be overloaded
    my ($self, $message) = @_;

    print STDERR $message."\n";
}

sub error_exit { # to be overloaded
    my ($self, $message) = @_;

    $self->log($message);
    exit(1);
}

1;

