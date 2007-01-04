package Bio::Vega::DBSQL::AssemblyTagAdaptor;

use strict;
use Bio::Vega::AssemblyTag;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use base 'Bio::EnsEMBL::DBSQL::BaseFeatureAdaptor';

use Data::Dumper;

sub _tables {
  my $self = shift;
  return ['assembly_tag', 'at'];
}

sub _columns {
  my $self = shift;
  return qw(at.tag_id at.seq_region_id at.seq_region_start at.seq_region_end at.seq_region_strand at.tag_type at.tag_info);
}

sub _objs_from_sth {
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

sub remove {
  my ($self, $del_at) = @_;
  eval {
  my $sql = "DELETE FROM assembly_tag where tag_id = ?";
  my $sth = $self->prepare($sql);
  $sth->execute($del_at->dbID);
  };
  if ($@){
	 throw "problem with deleting assembly_tag ".$del_at->dbID;
  }
  warning "----- assembly_tag tag_id ", $del_at->dbID, " is deleted -----\n";

  #assembly tag is on a chromosome slice,transform to get a clone_slice
  my $new_at = $del_at->transform('clone');
  my $clone_slice=$new_at->slice;
  my $sa=$self->db->get_SliceAdaptor();
  my $clone_id=$sa->get_seq_region_id($clone_slice);
  eval{
	 $self->update_assembly_tagged_clone($clone_id,"no");
  };
  if ($@){
	 throw "delete of assembly_tag failed :$@";
  }
  return 1;
}

sub update_assembly_tagged_clone {
  my ($self, $clone_id,$transferred) = @_;
  my $res;
  eval{
	 my $sql = "UPDATE assembly_tagged_clone SET transferred = ? WHERE clone_id = ?";
	 my $sth = $self->prepare($sql);
	 $res=$sth->execute($transferred,$clone_id);
	 $sth->finish;
  };
  if ($@) {
	 throw "update failed:$@";
  }
  if ($res != 1){
	 throw "update of assembly_tagged_clone failed:$clone_id may not be present";
  }
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
  my $chr_slice = $at->slice;
  unless ($chr_slice) {
	 throw "AssemblyTag does not have a slice attached to it, cannot store AssemblyTag\n";
  }
  my $sa = $self->db->get_SliceAdaptor();
  my $seq_region_id=$sa->get_seq_region_id($chr_slice);
  my $sql = "INSERT INTO assembly_tag (seq_region_id, seq_region_start, seq_region_end, seq_region_strand, tag_type, tag_info) VALUES (?,?,?,?,?,?)";
  my $sth = $self->prepare($sql);
  eval{
	 $sth->execute($seq_region_id, $at->seq_region_start, $at->seq_region_end, $at->seq_region_strand, $at->tag_type, $at->tag_info);
  };
  if ($@){
	 throw "insert of assembly_tag failed:$@";
  }
  #update also assembly_tagged_clone table, which is initially populated with all clones having transferred col. set to "no"
  #assembly tag is on a chromosome slice,transform to get a clone_slice
  my $new_at = $at->transform('contig');
  unless ($new_at) {
	 print STDERR "assembly tag not loaded tag_info:".$at->tag_info." tag_type:".$at->tag_type." seq_region_start:".$at->seq_region_start." seq_region_end:".$at->seq_region_end." seq_region_id:".$seq_region_id."\n";
	 throw "assembly tag $at cannot be transformed onto a contig slice from chromosome \n";
  }
  my $contig_slice=$new_at->slice;
  my $contig_id=$sa->get_seq_region_id($contig_slice);
  $sql = "select a.asm_seq_region_id from assembly a,seq_region s,coord_system c where a.cmp_seq_region_id=? and a.asm_seq_region_id=s.seq_region_id and s.coord_system_id=c.coord_system_id and c.name='clone'";
  $sth = $self->prepare($sql);
  $sth->execute($contig_id);
  my $clone_id;
  if (my $ref = $sth->fetchrow_hashref) {
	 $clone_id=$ref->{asm_seq_region_id};
  }
  unless ($clone_id) {
	 throw "clone_id not fetched\n";
  }
  eval {
	 $self->update_assembly_tagged_clone($clone_id,"yes");
  };
  if ($@){
	 throw "Update of assembly_tagged_clone table for clone_id:$clone_id not done\n".$@;
  }

  return 1;


}


1;

__END__

=head1 NAME - Bio::Vega::DBSQL::AssemblyTagAdaptor

=head1 AUTHOR

Chao-Kung Chen ck1@sanger.ac.uk

Re-engineered by Sindhu Pillai sp1@sanger.ac.uk
