package Bio::Otter::AssemblyTag;

use strict;

use vars qw(@ISA);
@ISA = qw(Bio::EnsEMBL::SeqFeature);



sub new {
  my($class) = @_;

  my $self = {};

  return bless $self, $class;
}

# start, end, and strand methods are inherited


sub tag_id {
  my ($self, $val) = @_;
  if ($val){
    $self->{tag_id} = $val;
  }

  return $self->{tag_id};
}

sub contig_id {
  my ($self, $val) = @_;
  if ($val){
    $self->{contig_id} = $val;
  }

  return $self->{contig_id};
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


1;
