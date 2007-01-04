package Bio::Vega::AssemblyTag;

use strict;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use base 'Bio::EnsEMBL::Feature';

sub new {

  my($class,@args) = @_;
  my $self = $class->SUPER::new(@args);
  my ($tag_type,$tag_info)  = rearrange([qw(TAG_TYPE TAG_INFO)],@args);
  $self->tag_type($tag_type);
  $self->tag_info($tag_info);
  return $self;

}

# start, end, strand, dbID(tag_id), slice methods are inherited

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

1;
