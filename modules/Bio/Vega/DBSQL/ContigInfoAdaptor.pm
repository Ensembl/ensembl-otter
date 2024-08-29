=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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

package Bio::Vega::DBSQL::ContigInfoAdaptor;

use strict;
use warnings;
use Bio::Vega::ContigInfo;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Vega::Utils::Comparator qw(compare);

use base qw(Bio::EnsEMBL::DBSQL::BaseAdaptor);


    # kept for compatibility:
sub fetch_by_seq_region_id {
    my ($self, $seq_region_id) = @_;

    my $contigSlice=$self->db->get_SliceAdaptor->fetch_by_seq_region_id($seq_region_id);

    return $self->fetch_by_contigSlice( $contigSlice );
}

sub fetch_by_contigSlice {
    my ($self, $contigSlice) = @_;

    if($contigSlice->coord_system_name() ne 'contig') {
        throw("the only argument has to be a contig slice");
    }

    my $seq_region_id = $contigSlice->get_seq_region_id();

    my $sth = $self->prepare(q{
        SELECT contig_info_id, author_id, }.$self->db->dbc->from_date_to_seconds('created_date').q{
          FROM contig_info
         WHERE seq_region_id = ?
           AND is_current
    });
    $sth->execute($seq_region_id);

        # created_date is only set for contig_info objects that either come directly
        # from the DB (this case) or have just been stored.
        # Since the date is not a part of XML, the XML->Vega parser will leave the date unset.
    my ($contiginfo_id, $author_id, $created_uniseconds) = $sth->fetchrow_array();
    return unless $sth->rows();

    $sth->finish();
    my $author=$self->db->get_AuthorAdaptor->fetch_by_dbID($author_id);
    my $contig_info= Bio::Vega::ContigInfo->new(
        -dbID           => $contiginfo_id,
        -SLICE          => $contigSlice,
        -AUTHOR         => $author,
        -CREATED_DATE   => $created_uniseconds,
    );

    my $attributes = $self->db->get_AttributeAdaptor->fetch_all_by_ContigInfo($contig_info);
    $contig_info->add_Attributes(@$attributes);

    return $contig_info;
}


sub store {
    my ($self, $contig_info, $time_uniseconds) = @_;

    unless ($contig_info) {
        $self->throw("Must provide a ContigInfo object to the store method");
    } elsif (! $contig_info->isa("Bio::Vega::ContigInfo")) {
        $self->throw("Argument '$contig_info' to the store method must be a ContigInfo object.");
    }

    my $contigSlice = $contig_info->slice
        || throw('Cannot store contig_info without attached slice');

        # longer but better way than the following 'shorthand':
        #       my $seq_region_id = $contigSlice->get_seq_region_id();

    my $seq_region_id = $self->db->get_SliceAdaptor->get_seq_region_id($contigSlice);

    unless(defined $seq_region_id) {
        throw ('no dbID for slice, cannot store contig_info\n');
    }

    my $db_contig_info = $self->fetch_by_contigSlice($contigSlice);
    my $changed = not $db_contig_info;

        # if any clone_info exists for the same slice then make it non-current:
    if($db_contig_info) {
        if( $changed = compare($contig_info, $db_contig_info) ) {
            my $sth=$self->prepare(q{UPDATE contig_info
                                        SET is_current = 0
                                      WHERE seq_region_id = ?
            });
            $sth->execute($seq_region_id);
        }
    }

    if($changed) {
        eval{
                # this will have a 'magic' side-effect
                # of updating the author_id valid for THIS database
                # (in case the contig_info comes from a different one)
            $self->db->get_AuthorAdaptor->store($contig_info->author);
            1;
        } or throw "Error due to contig_info author: ".$contig_info->author->name
                 ." author_email: ".$contig_info->author->email
                 ." slice name: ".$contig_info->slice->name
                 ."\nerror is: ".$@;

        # Store a new row in the contig_info table and get contig_info_id
        my $created_date_fn = $self->db->dbc->from_seconds_to_date('?');
        my $sth = $self->prepare(qq{
                               INSERT INTO contig_info(
                               seq_region_id
                               , author_id
                               , created_date
                               , is_current)
                               VALUES (?,?,$created_date_fn,1)
        });

        my $created_date = $contig_info->created_date || $time_uniseconds || time;
        my $author_id    = $contig_info->author->dbID;
        $sth->execute( $seq_region_id,
                       $author_id,
                       $created_date,
        );


        my $contig_info_id = $self->last_insert_id('contig_info_id', undef, 'contig_info')
            or $self->throw("No insert id");
        $contig_info->dbID($contig_info_id);

            # created_date is only set for contig_info objects that either come directly
            # from the DB or have just been stored (this case).
            # Since the date is not a part of XML, the XML->Vega parser will leave the date unset.
        $contig_info->created_date( $created_date );

        $self->db->get_AttributeAdaptor->store_on_ContigInfo($contig_info,$contig_info->get_all_Attributes);
    }

    return $changed;
}

1;

__END__

=head1 NAME - Bio::Vega::DBSQL::ContigInfoAdaptor.pm

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

