
package Bio::Otter::Server::GFF::Patches;

use strict;
use warnings;
use Try::Tiny;

use base qw( Bio::Otter::Server::GFF );

use Bio::Vega::PatchMapper;

sub get_requested_features {
    my ($self) = @_;

    my $map = $self->make_map;
    my ($cs, $name, $type, $start, $end, $csver) = @{$map}{qw( cs name type start end csver )};

    my $chr_slice = $self->get_slice($self->otter_dba, $cs, $name, $type, $start, $end, $csver);
    my $patch_mapper = Bio::Vega::PatchMapper->new($chr_slice);
    my $features = $patch_mapper->all_features;

    return $features;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

