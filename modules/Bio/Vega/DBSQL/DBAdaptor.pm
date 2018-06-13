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


package Bio::Vega::DBSQL::DBAdaptor;

use strict;
use warnings;

use Bio::Vega::DBSQL::ContigInfoAdaptor;
use Bio::Vega::DBSQL::AuthorAdaptor;
use Bio::Vega::DBSQL::AuthorGroupAdaptor;
use Bio::Vega::DBSQL::AttributeAdaptor;
use Bio::Vega::DBSQL::GeneAdaptor;
use Bio::Vega::DBSQL::StableIdAdaptor;
use Bio::Vega::DBSQL::ExonAdaptor;
use Bio::Vega::DBSQL::TranscriptAdaptor;
use Bio::Vega::DBSQL::AssemblyTagAdaptor;
use Bio::Vega::DBSQL::MetaContainer;
use Bio::Vega::DBSQL::SliceAdaptor;
use Bio::Vega::DBSQL::SliceLockAdaptor;
use Bio::Vega::DBSQL::SplicedAlignFeature::DnaAdaptor;
use Bio::Vega::DBSQL::SplicedAlignFeature::ProteinAdaptor;

use base 'Bio::EnsEMBL::DBSQL::DBAdaptor';

## BE SURE TO MAINTAIN sub _adaptor_tag_list() below,
## if adding, renaming or removing adaptors.

sub get_GeneAdaptor {
  my ($self) = @_;
  if ( !exists $self->{'VegaGene'} ){
      my $ad=Bio::Vega::DBSQL::GeneAdaptor->new($self);
      $self->{'VegaGene'}=$ad;
  }
  return $self->{'VegaGene'};
}

sub get_SliceAdaptor {
  my ($self) = @_;
  if ( !exists $self->{'VegaSlice'} ){
      my $ad=Bio::Vega::DBSQL::SliceAdaptor->new($self);
      $self->{'VegaSlice'}=$ad;
  }
  return $self->{'VegaSlice'};
}

sub get_SliceLockAdaptor {
  my ($self) = @_;
  if ( !exists $self->{'VegaSliceLock'} ){
      my $ad=Bio::Vega::DBSQL::SliceLockAdaptor->new($self);
      $self->{'VegaSliceLock'}=$ad;
  }
  return $self->{'VegaSliceLock'};
}

sub get_ContigInfoAdaptor {
  my ($self) = @_;
  if ( !exists $self->{'ContigInfo'} ){
      my $ad=Bio::Vega::DBSQL::ContigInfoAdaptor->new($self);
      $self->{'ContigInfo'}=$ad;
  }
  return $self->{'ContigInfo'};
}

sub get_AuthorAdaptor {
  my ($self) = @_;
  if ( !exists $self->{'Author'} ){
      my $ad=Bio::Vega::DBSQL::AuthorAdaptor->new($self);
      $self->{'Author'}=$ad;
  }
  return $self->{'Author'};
}

sub get_AuthorGroupAdaptor {
  my ($self) = @_;
  if ( !exists $self->{'AuthorGroup'} ){
      my $ad=Bio::Vega::DBSQL::AuthorGroupAdaptor->new($self);
      $self->{'AuthorGroup'}=$ad;
  }
  return $self->{'AuthorGroup'};
}

sub get_AttributeAdaptor {
  my ($self) = @_;
  if ( !exists $self->{'ContigAttribute'} ){
      my $ad=Bio::Vega::DBSQL::AttributeAdaptor->new($self);
      $self->{'ContigAttribute'}=$ad;
  }
  return $self->{'ContigAttribute'};
}

sub get_StableIdAdaptor {
  my ($self) = @_;
  if ( !exists $self->{'StableId'} ){
      my $ad=Bio::Vega::DBSQL::StableIdAdaptor->new($self);
      $self->{'StableId'}=$ad;
  }
  return $self->{'StableId'};
}

sub get_ExonAdaptor {
  my ($self) = @_;
  if ( !exists $self->{'VegaExon'} ){
      my $ad=Bio::Vega::DBSQL::ExonAdaptor->new($self);
      $self->{'VegaExon'}=$ad;
  }
  return $self->{'VegaExon'};
}

sub get_TranscriptAdaptor {
  my ($self) = @_;
  if ( !exists $self->{'VegaTranscript'} ){
      my $ad=Bio::Vega::DBSQL::TranscriptAdaptor->new($self);
      $self->{'VegaTranscript'}=$ad;
  }
  return $self->{'VegaTranscript'};
}

# sub get_TranslationAdaptor no longer exists!
# We now rebless Translation inside Bio::Vega::Transcript::reincarnate_transcript() instead

sub get_AssemblyTagAdaptor {
  my ($self) = @_;
  if ( !exists $self->{'AssemblyTag'} ){
      my $ad=Bio::Vega::DBSQL::AssemblyTagAdaptor->new($self);
      $self->{'AssemblyTag'}=$ad;
  }
  return $self->{'AssemblyTag'};
}

sub get_DnaSplicedAlignFeatureAdaptor {
  my ($self) = @_;
  if ( !exists $self->{'VegaSplicedAlignFeatureDNA'} ){
      my $ad=Bio::Vega::DBSQL::SplicedAlignFeature::DnaAdaptor->new($self);
      $self->{'VegaSplicedAlignFeatureDNA'}=$ad;
  }
  return $self->{'VegaSplicedAlignFeatureDNA'};
}

sub get_ProteinSplicedAlignFeatureAdaptor {
  my ($self) = @_;
  if ( !exists $self->{'VegaSplicedAlignFeatureProtein'} ){
      my $ad=Bio::Vega::DBSQL::SplicedAlignFeature::ProteinAdaptor->new($self);
      $self->{'VegaSplicedAlignFeatureProtein'}=$ad;
  }
  return $self->{'VegaSplicedAlignFeatureProtein'};
}

sub get_MetaContainer {
  my ($self) = @_;
  if ( !exists $self->{'VegaMetaContainer'} ){
      $self->{'VegaMetaContainer'}=Bio::Vega::DBSQL::MetaContainer->new($self);
  }
  return $self->{'VegaMetaContainer'};
}

sub get_AnnotationBroker {
  my ($self) = @_;
  if ( !exists $self->{'AnnotationBroker'} ){
      $self->{'AnnotationBroker'}=Bio::Vega::AnnotationBroker->new($self);
  }
  return $self->{'AnnotationBroker'};
}

sub begin_work {
  my ($self) = @_;
  $self->dbc->do('BEGIN');
  return;
}

sub commit {
  my ($self) = @_;
  $self->dbc->do('COMMIT');
  return;
}

sub rollback {
  my ($self) = @_;
  $self->dbc->do('ROLLBACK');
  return;
}

sub _adaptor_tag_list {
    return qw{
        VegaGene
        VegaSlice
        ContigInfo
        Author
        AuthorGroup
        ContigAttribute
        SliceLock
        StableId
        VegaExon
        VegaTranscript
        AssemblyTag
        VegaSplicedAlignFeatureDNA
        VegaSplicedAlignFeatureProtein
        VegaMetaContainer
        AnnotationBroker
    };
}

sub clear_caches {
    my ($self) = @_;
    foreach my $adaptor_tag ( $self->_adaptor_tag_list() ) {
        my $adaptor = $self->{$adaptor_tag};
        if ($adaptor and $adaptor->can('clear_cache')) {
            $adaptor->clear_cache();
        }
    }
    return $self->SUPER::clear_caches();
}


1;
__END__

=head1 NAME - Bio::Vega::DBSQL::DBAdaptor.pm

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

