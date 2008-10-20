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

  my ($chr_name, $chr_slice, @chr_coords);

  foreach my $seg (@$ctg_projection) {
    my $ctg = $seg->to_Slice();
    #printf("== %s %d %d\n", $ctg->seq_region_name, $ctg->start, $ctg->end);

    # now find the chromosome name of current assembly
    # only do this once as all contigs in this projection will be on same chr.
    unless ( $chr_name ){
      $chr_name = $self->_fetch_chr_name_by_contig_name($ctg->seq_region_name);
      $chr_slice = $self->fetch_by_region('chromosome', $chr_name, undef, undef, undef, 'otter');
    }

    # now project the contig to current chr. slice
    my $chr_projection = $ctg->project_to_slice($chr_slice); # not project()
    foreach my $chr (@$chr_projection) {
      my $pchr_slice = $chr->to_Slice();
      push(@chr_coords, $pchr_slice->start, $pchr_slice->end);
      #printf("%s %d %d\n\n", $pchr_slice->seq_region_name, $pchr_slice->start, $pchr_slice->end);
    }
  }
  my @sorted = sort {$a<=>$b} @chr_coords;

  my $slice = $self->fetch_by_region('chromosome', $chr_name, $sorted[0], $sorted[-1]);

  return $slice ? $slice : throw("Could not fetch chromosome slice for $subregion_name");
}

sub _fetch_chr_name_by_contig_name {

  my ($self, $ctgname) = @_;
  my $loutre_db = $self->db;

  my $chrqry = $loutre_db->dbc->prepare(qq{
                                           SELECT sr.name
                                           FROM seq_region sr, seq_region_attrib sa, attrib_type at
                                           WHERE sr.name like 'chr%' and sr.seq_region_id IN (
                                             SELECT asm_seq_region_id
                                             FROM assembly
                                             WHERE cmp_seq_region_id IN (
                                               SELECT seq_region_id
                                               FROM seq_region
                                               WHERE name = ?
                                             )
                                           )
                                           AND sr.seq_region_id = sa.seq_region_id
                                           AND sa.attrib_type_id = at.attrib_type_id
                                           AND at.code = 'write_access'
                                           AND sa.value = 1
                                         });
  $chrqry->execute($ctgname);

  return $chrqry->fetchrow;
}


1;


