=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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


package Bio::Vega::DBSQL::SliceAdaptor;

use strict;
use warnings;

use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use base 'Bio::EnsEMBL::DBSQL::SliceAdaptor';

sub fetch_by_subregion {

  # returns chr. slice of the subregion

  my ($self, $subregion_name) = @_;

  my $subr_slice = $self->fetch_by_region('subregion', $subregion_name, undef, undef, undef, undef);

  # as there is no mapping defined between chromosome and subregion
  # we need to first project subregion slice to contig
  # and find all the contigs in the projection;
  # then find the start/end of the latest chromosome assembly for the contigs
  # to work out the chromosome start/end of the subregion

  my $ctg_projection = $subr_slice->project('contig');
  my ($chr_name, @chr_coords) = $self->_fetch_chr_coords_by_contig_projection($ctg_projection);

  my $slice = $self->fetch_by_region('chromosome', $chr_name, $chr_coords[0], $chr_coords[-1]);

  return $slice ? $slice : throw("Could not fetch chromosome slice for $subregion_name");
}

sub fetch_by_clone_list {
  # Given a list of clones (acc.sv)
  # returns the chr. slice of the region
  # spanning from start to end of the ordered clones
  # Useful to get the chr. subregion of mouse encodes,
  # because they are not defined as subregions like those of the human ones

  my ($self, $clones) = @_;

  my $counter = 0;
  my $seq_region_name;
  my @chr_coords;

  foreach my $acc_sv (@$clones){
    #warn $acc_sv;
    my $clone_slice = $self->fetch_by_region('clone', $acc_sv);
    my $ctg_projection = $clone_slice->project('contig');

    my($chrname, @coords) = $self->_fetch_chr_coords_by_contig_projection($ctg_projection);
    if ( @coords ){
      push(@chr_coords, @coords);
      $seq_region_name = $chrname unless $seq_region_name;
    }
  }

  my @sorted = sort {$a<=>$b} @chr_coords;

  my $slice = $self->fetch_by_region('chromosome', $seq_region_name, $sorted[0], $sorted[-1]);

  return $slice ? $slice : throw("Could not fetch chromosome slice from clone list");
}

sub _fetch_chr_coords_by_contig_projection {

  my ($self, $ctg_projection) = @_;

  my ($seq_region_name, $chr_slice, @chr_coords);

  foreach my $seg (@$ctg_projection) {
    my $ctg = $seg->to_Slice();
    #printf("== %s %d %d\n", $ctg->seq_region_name, $ctg->start, $ctg->end);

    # now find the chromosome name of current assembly
    # only do this once as all contigs in this projection will be on same chr.

    unless ( $seq_region_name ){
      eval{
        $seq_region_name = $self->_fetch_chr_name_by_contig_name($ctg->seq_region_name);
        $chr_slice = $self->fetch_by_region('chromosome', $seq_region_name, undef, undef, undef, 'otter');
        1;
      } or die
          "Cannot project ", $ctg->seq_region_name,
          " to seq_region ... please check that your list is up-to-date\n";
    }

    # now project the contig to current chr. slice
    my $chr_projection = $ctg->project_to_slice($chr_slice); # not project()
    foreach my $chr (@$chr_projection) {
      my $pchr_slice = $chr->to_Slice();
      push(@chr_coords, $pchr_slice->start, $pchr_slice->end);
      #printf("%s %d %d\n\n", $pchr_slice->seq_region_name, $pchr_slice->start, $pchr_slice->end);
    }
  }

  my @sorted_coords = sort {$a<=>$b} @chr_coords;
  return ($seq_region_name, @sorted_coords);
}

sub _fetch_chr_name_by_contig_name {

  my ($self, $ctgname) = @_;
  my $loutre_db = $self->db;

  my $chrqry = $loutre_db->dbc->prepare(qq{SELECT sr.name
                                           FROM seq_region sr,
                                                seq_region_attrib sa,
                                                attrib_type at
                                           WHERE sr.name
                                           LIKE 'chr%'
                                           AND sr.seq_region_id
                                           IN (SELECT asm_seq_region_id
                                               FROM assembly
                                               WHERE cmp_seq_region_id
                                           IN (SELECT seq_region_id
                                               FROM seq_region
                                               WHERE name = ?))
                                           AND sr.seq_region_id = sa.seq_region_id
                                           AND sa.attrib_type_id = at.attrib_type_id
                                           AND sa.value =1
                                           AND at.code='write_access'
                                         });

  $chrqry->execute($ctgname);

  return $chrqry->fetchrow;
}


1;

__END__

=head1 NAME - Bio::Vega::DBSQL::SliceAdaptor;

=head1 DESCRIPTION

Not sure if this is actually used!

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

