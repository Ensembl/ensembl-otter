# Dummy B:O:Lace::Client

package OtterTest::Client;

use strict;
use warnings;

use Bio::Otter::Utils::MM;
use Bio::Otter::Server::Config;

sub new {
    my ($pkg) = @_;
    return bless {}, $pkg;
}

sub get_accession_types {
    my ($self, @accessions) = @_;
    my $types = $self->mm->get_accession_types(\@accessions);
    # FIXME: de-serialisation is in wrong place: shouldn't need to serialise here.
    # see apache/get_accession_types and AccessionTypeCache.
    my $response = '';
    foreach my $acc (keys %$types) {
        $response .= join("\t", $acc, @{$types->{$acc}}) . "\n";
    }
    return $response;
}

sub mm {
    my $self = shift;
    return $self->{_mm} ||= Bio::Otter::Utils::MM->new;
}

# FIXME: scripts/apache/get_config needs reimplementing with a Bio::Otter::ServerAction:: class,
#        which we can then use here rather than duplicating the file names.
#
sub get_otter_schema {
    my $self = shift;
    return Bio::Otter::Server::Config->get_file('otter_schema.sql');
}

sub get_loutre_schema {
    my $self = shift;
    return Bio::Otter::Server::Config->get_file('loutre_schema_sqlite.sql');
}

1;
