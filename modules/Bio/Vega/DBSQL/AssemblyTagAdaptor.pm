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

package Bio::Vega::DBSQL::AssemblyTagAdaptor;

use strict;
use warnings;
use Bio::Vega::AssemblyTag;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);

use base 'Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor';

sub _tables { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
  my ($self) = @_;
  return ['assembly_tag', 'at'];
}

sub _columns { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
  my ($self) = @_;
  return qw(at.tag_id at.seq_region_id at.seq_region_start at.seq_region_end at.seq_region_strand at.tag_type at.tag_info);
}

sub _objs_from_sth { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
  my ($self, $sth) = @_;
  my $a_tags = [];
  my $hashref;
  while ($hashref = $sth->fetchrow_hashref()) {
    my $atags = Bio::Vega::AssemblyTag->new();
    $atags->seq_region_id($hashref->{seq_region_id});
    $atags->seq_region_strand  ($hashref->{seq_region_strand});
    $atags->seq_region_start   ($hashref->{seq_region_start});
    $atags->seq_region_end     ($hashref->{seq_region_end});
    $atags->tag_type($hashref->{tag_type});
    !$hashref->{tag_info} ?  ($atags->tag_info("-")) : ($atags->tag_info($hashref->{tag_info}));
    push @$a_tags, $atags;
  }
  return $a_tags;
}

sub list_dbIDs {
   my ($self) = @_;
   return $self->_list_dbIDs("assembly_tag");
}

sub check_seq_region_id_is_transferred {

  my ($self, $seq_region_id) = @_;
  my $sth = $self->prepare(qq{
SELECT seq_region_id
FROM assembly_tagged_contig
WHERE seq_region_id = $seq_region_id
AND transferred = 'yes'
limit 1
}
      );
  $sth->execute;
  return $sth->fetchrow ? 1 : 0;
}

sub remove {
  my ($self, $del_at) = @_;
  my $sth;
  eval {
      $sth = $self->prepare("DELETE FROM assembly_tag where tag_id = ?");
      $sth->execute($del_at->dbID);
      1;
  } or throw "problem with deleting assembly_tag ".$del_at->dbID;
  my $num=$sth->rows;
  if ($num == 0) {
      throw "assembly tag with ".$del_at->dbID." not deleted , tag_id may not be present\n";
  }
  warning "----- assembly_tag tag_id ", $del_at->dbID, " is deleted -----\n";

  #assembly tag is on a chromosome slice,transform to get a clone_slice
  my $new_at = $del_at->transform('clone');
  my $clone_slice=$new_at->slice;
  my $sa=$self->db->get_SliceAdaptor();
  my $clone_id=$sa->get_seq_region_id($clone_slice);
  eval{
      $self->update_assembly_tagged_clone($clone_id,"no");
      1;
  } or throw "delete of assembly_tag failed :$@";
  return 1;
}

sub update_assembly_tagged_contig {
  my ($self, $seq_region_id) = @_;

  my $num;
  eval{
      my $sth = $self->prepare(qq{
UPDATE assembly_tagged_contig
SET transferred = 'yes'
WHERE seq_region_id = $seq_region_id
});
      $sth->execute();
      1;
  } or throw "Update of assembly_tagged_contig failed for seq_region_id $seq_region_id: $@";

  return 1;
}

sub store {
  my ($self, $at) = @_;
  if (!ref $at || !$at->isa('Bio::Vega::AssemblyTag') ) {
    throw("Must store an AssemblyTag object, not a $at");
  }
  if ($at->is_stored($self->db->dbc)) {
    return $at->dbID();
  }

  # Assembly tags use contig coords rather than chrom. coords.
  # if assembly tag is on a chromosome slice, transform it to get a contig_slice
  # => XML dump has atags on chr. slice, but fetch_assembly_tags_for_loutre script prepares atags in contig slice already

  my $contig_slice;

  if ( $at->slice->coord_system->name ne "contig") {
    my $at_c = $at->transform('contig');
    unless ($at_c){
      throw("assembly tag $at cannot be transformed onto a contig slice from chromosome \n" .
            "assembly tag not loaded tag_info:".$at->tag_info." tag_type:".$at->tag_type.
            " seq_region_start:".$at->seq_region_start." seq_region_end:".$at->seq_region_end);
    }

    $contig_slice = $at_c->slice;

    unless ($contig_slice) {
      throw "AssemblyTag does not have a contig slice attached to it, cannot store AssemblyTag\n";
    }
  }
  else {
    $contig_slice = $at->slice;
  }

  my $sa = $self->db->get_SliceAdaptor();
  my $seq_region_id=$sa->get_seq_region_id($contig_slice);

  my $sql = "INSERT IGNORE INTO assembly_tag (seq_region_id, seq_region_start, seq_region_end, seq_region_strand, tag_type, tag_info) VALUES (?,?,?,?,?,?)";
  my $sth = $self->prepare($sql);

  eval{
      $sth->execute($seq_region_id, $at->seq_region_start, $at->seq_region_end, $at->seq_region_strand, $at->tag_type, $at->tag_info);
      1;
  } or throw "insert of assembly_tag failed:$@";

  $self->update_assembly_tagged_contig($seq_region_id); # is contig_id

  return 1;
}


1;

__END__

=head1 NAME - Bio::Vega::DBSQL::AssemblyTagAdaptor

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

