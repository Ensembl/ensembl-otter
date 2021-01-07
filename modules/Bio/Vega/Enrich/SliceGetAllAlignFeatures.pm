=head1 LICENSE

Copyright [2018-2021] EMBL-European Bioinformatics Institute

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

### Bio::Vega::Enrich::SliceGetAllAlignFeatures

package Bio::Vega::Enrich::SliceGetAllAlignFeatures;

use strict;
use warnings;

use Bio::EnsEMBL::Slice;
use Bio::Otter::Utils::RequireModule qw(require_module);
use Bio::Vega::DBSQL::SimpleBindingAdaptor;

# Code in this module was originally embedded in Bio::Otter::Server::Support::Web

sub enrich {
    my ($afs, $enriched_class) = @_;

    require_module($enriched_class);

    # Put the names into the hit_description hash:
    my %hd_hash = ();
    foreach my $af (@$afs) {
        $hd_hash{$af->hseqname()} = '';
    }

    return $afs unless %hd_hash; # @$afs was empty

    # Fetch the hit descriptions from the pipeline, if we have a hit_description table

    # WARNING: We ASSUME that the features have already been fetched from a database
    # and get the connector from the first feature

    # Check for hit_description table
    my $pdbc = $afs->[0]->adaptor->dbc;
    return $afs unless $pdbc->db_handle->tables(undef, undef, 'hit_description', undef);

    my $hd_adaptor = Bio::Vega::DBSQL::SimpleBindingAdaptor->new( $pdbc );
    $hd_adaptor->fetch_into_hash(
        'hit_description',
        'hit_name',
        { qw(
            hit_name _hit_name
            hit_length _hit_length
            hit_description _description
            hit_taxon _taxon_id
            hit_db _db_name
        )},
        'Bio::Vega::HitDescription',
        \%hd_hash,
    );

    foreach my $af (@$afs) {
        if(my $hd = $hd_hash{$af->hseqname()}) {
            bless $af, $enriched_class;
            $af->{'_hit_description'} = $hd;
        }
    }

    return $afs;
}

# It is  a lucky  coincidence that these  two classes need  to be  enriched, and
# their fetching methods in Bio::EnsEMBL::Slice are not systematically named. We
# make  use of  this coincidence  by enriching  the methods  without subclassing
# Bio::EnsEMBL::Slice

sub Bio::EnsEMBL::Slice::get_all_DnaDnaAlignFeatures {
    my ($self, @args) = @_;

    return $self->get_all_DnaAlignFeatures(@args);
    # my $naked_features = $self->get_all_DnaAlignFeatures(@args);
    # return enrich($naked_features, 'Bio::Vega::DnaDnaAlignFeature');
}

sub Bio::EnsEMBL::Slice::get_all_DnaPepAlignFeatures {
    my ($self, @args) = @_;

    return $self->get_all_ProteinAlignFeatures(@args);
    # my $naked_features = $self->get_all_ProteinAlignFeatures(@args);
    # return enrich($naked_features, 'Bio::Vega::DnaPepAlignFeature');
}

1;

__END__

=head1 NAME - Bio::Vega::Enrich::SliceGetAllAlignFeatures

=head1 DESCRIPTION

Adds the following enriched C<< get_all_<type>AlignFeatures >> methods to
Bio::EnsEMBL::Slice, which return corresponding features enriched 
with original feature data, including full feature length, from
the hit_description table, if it exists.

=head2 Bio::EnsEMBL::Slice::get_all_DnaDnaAlignFeatures

Calls Bio::EnsEMBL::Slice::get_all_DnaAlignFeatures and then
enriches the results with Bio::Vega::HitFeatures if possible.

=head2 Bio::EnsEMBL::Slice::get_all_DnaPepAlignFeatures

Calls Bio::EnsEMBL::Slice::get_all_ProteinAlignFeatures and then
enriches the results with Bio::Vega::HitFeatures if possible.

=head1 SEE ALSO

L<Bio::Vega::DnaDnaAlignFeature>
L<Bio::Vega::DnaPepAlignFeature>
L<Bio::Vega::HitDescription>

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

# EOF
