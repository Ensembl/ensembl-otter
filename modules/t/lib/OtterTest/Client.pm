# Dummy B:O:Lace::Client

package OtterTest::Client;

use strict;
use warnings;

use Bio::Otter::Utils::MM;

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

1;
