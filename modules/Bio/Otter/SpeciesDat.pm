
package Bio::Otter::SpeciesDat;

# Read a set of datasets from a file.
#
# Author: lg4

use strict;
use warnings;

use Try::Tiny;
use Carp;
use Bio::Otter::SpeciesDat::DataSet;

# Consider using Bio::Otter::Server::Config->SpeciesDat or
# $server->allowed_datasets instead.
sub new {
    my ($pkg, $file) = @_;
    my $dataset_hash = _dataset_hash($file);
    my %dataset;
    while (my ($name, $info) = each %$dataset_hash) {
        try {
            my %param =
              (%$info,
               $pkg->_spec2list($name, $info->{DBSPEC}, ''),
               $pkg->_spec2list($name, $info->{DNA_DBSPEC}, 'DNA_'));
            $dataset{$name} = Bio::Otter::SpeciesDat::DataSet->new($name, \%param);
        } catch {
            croak "Dataset $name from $file: $_";
        };
    }
    my $new = {
        _dataset  => \%dataset,
        _datasets => [ values %dataset ],
    };
    bless $new, $pkg;
    return $new;
}

sub _spec2list {
    my ($pkg, $ds_name, $dbspec, $prefix) = @_;
    die "no dbspec - old species.dat ?" unless $dbspec;
    my $db = Bio::Otter::Server::Config->Database($dbspec);
    return ("${prefix}HOST" => $db->host,
            "${prefix}PORT" => $db->port,
            "${prefix}USER" => $db->user,
            $db->pass_maybe("${prefix}PASS"));
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

    my $cursect = undef;
    my $defhash = {};
    my $curhash = undef;
    my $sp = {};

    my $do_line = sub {
        return if /^\#/;
        return unless /\w+/;
        chomp;

        if (/\[(.*)\]/) {
            if (!defined($cursect) && $1 ne "defaults") {
                die "Error: first section in species.dat should be 'defaults'";
            }
            elsif ($1 eq "defaults") {
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
    };

    open my $dat, '<', $filename or die "Can't read species file '$filename' : $!";
    while (<$dat>) { $do_line->(); }
    close $dat or die "Error reading '$filename' : $!";

    # Have finished with defaults, so we can remove them.
    delete $sp->{'defaults'};

    return $sp;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

