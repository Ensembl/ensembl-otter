package Bio::Vega::AssemblyTag;

use strict;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use base 'Bio::EnsEMBL::Feature';

sub new {

  my($class,@args) = @_;
  my $self = $class->SUPER::new(@args);
  my ($contig_id,$contig_name,$tag_type,$tag_info)  = rearrange([qw(CONTIG_ID CONTIG_NAME TAG_TYPE TAG_INFO)],@args);
  $self->contig_id($contig_id);
  $self->contig_name($contig_name);
  $self->tag_type($tag_type);
  $self->tag_info($tag_info);
  return $self;

}

# start, end, strand, dbID(tag_id) methods are inherited

##future this method can go away as we need only the contig_name method and create a contig_slice to which
##the assembly tag object can be attached

sub contig_id {
  my ($self, $val) = @_;
  if ($val){
    $self->{contig_id} = $val;
  }

  return $self->{contig_id};
}

sub contig_name {
  my ($self, $val) = @_;
  if ($val){
    $self->{contig_name} = $val;
  }

  return $self->{contig_name};
}

sub tag_type {
 my ($self, $val) = @_;
  if ($val){
    $self->{tag_type} = $val;
  }

  return $self->{tag_type};
}

sub tag_info {
 my ($self, $val) = @_;
  if ($val){
    $self->{tag_info} = $val;
  }

  return $self->{tag_info};
}

sub slice_by_contig_id {

  my ($self,$contig_id)=@_;
  my $sa=$self->db->get_SliceAdaptor;
  my $slice=$sa->fetch_by_seq_region_id($contig_id);
  $self->{'slice'}=$slice;
  return $slice;

}

sub slice_by_contig_name {

  my ($self,$contig_name)=@_;
  my $sa=$self->db->get_SliceAdaptor;
  my $slice=$sa->fetch_by_region('contig',$contig_name);
  $self->{'slice'}=$slice;
  return $slice;

}

1;
