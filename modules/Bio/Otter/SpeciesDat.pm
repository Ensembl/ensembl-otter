
package Bio::Otter::SpeciesDat;

# Read a set of datasets from a file.
#
# Author: lg4

use strict;
use warnings;

use Bio::Otter::SpeciesDat::DataSet;

sub new {
    my ($pkg, $file) = @_;
    my $dataset_hash = _dataset_hash($file);
    my $dataset = {
        map {
            $_ => Bio::Otter::SpeciesDat::DataSet->new($_, $dataset_hash->{$_});
        } keys %{$dataset_hash} };
    my $datasets = [ values %{$dataset} ];
    my $new = {
        _dataset  => $dataset,
        _datasets => $datasets,
    };
    bless $new, $pkg;
    return $new;
}

sub dataset {
    my ($self, $name) = @_;
    return $self->{_dataset}{$name};
}

sub datasets {
    my ($self) = @_;
    return $self->{_datasets};
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

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

