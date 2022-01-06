=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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

package Bio::Vega::AssemblyTag;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use base 'Bio::EnsEMBL::Feature';

sub new {

  my ($class, @args) = @_;
  my $self = $class->SUPER::new(@args);
  my ($seq_region_id, $seq_region_start, $seq_region_end, $seq_region_strand, $tag_type, $tag_info) =
    rearrange([qw(SEQ_REGION_ID SEQ_REGION_START SEQ_REGION_END SEQ_REGION_STRAND TAG_TYPE TAG_INFO)],@args);

  $self->tag_type($seq_region_id);
  $self->tag_type($seq_region_start);
  $self->tag_type($seq_region_end);
  $self->tag_type($seq_region_strand);
  $self->tag_type($tag_type);
  $self->tag_info($tag_info);
  return $self;

}

# although start, end, strand, dbID(tag_id) can be inherited
# the assembly_tag has "seq_region_" prefixed

sub seq_region_id {
 my ($self, $val) = @_;
  if ($val){
    $self->{seq_region_id} = $val;
  }

  return $self->{seq_region_id};
}

sub seq_region_start {
 my ($self, $val) = @_;
  if ($val){
    $self->{seq_region_start} = $val;
  }

  return $self->{seq_region_start};
}

sub seq_region_end {
 my ($self, $val) = @_;
  if ($val){
    $self->{seq_region_end} = $val;
  }

  return $self->{seq_region_end};
}

sub seq_region_strand {
 my ($self, $val) = @_;
  if ($val){
    $self->{seq_region_strand} = $val;
  }

  return $self->{seq_region_strand};
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

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

