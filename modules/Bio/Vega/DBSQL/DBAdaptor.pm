package Bio::Vega::DBSQL::DBAdaptor;

use Bio::Vega::DBSQL::ContigInfoAdaptor;
use Bio::Vega::DBSQL::AuthorAdaptor;
use Bio::Vega::DBSQL::AuthorGroupAdaptor;
use Bio::Vega::DBSQL::AttributeAdaptor;
use Bio::Vega::DBSQL::GeneAdaptor;
use Bio::Vega::DBSQL::StableIdAdaptor;
use Bio::Vega::DBSQL::ExonAdaptor;
use Bio::Vega::DBSQL::TranscriptAdaptor;
#use Bio::Vega::DBSQL::TranslationAdaptor;
use Bio::Vega::DBSQL::AssemblyTagAdaptor;
use Bio::Vega::DBSQL::ContigLockAdaptor;
use Bio::Vega::DBSQL::MetaContainer;
use base 'Bio::EnsEMBL::DBSQL::DBAdaptor';

sub get_GeneAdaptor {
  my $self = shift;
  if ( !exists $self->{'VegaGene'} ){
	 my $ad=Bio::Vega::DBSQL::GeneAdaptor->new($self);
	 $self->{'VegaGene'}=$ad;
  }
  return $self->{'VegaGene'};
}

sub get_ContigInfoAdaptor {
  my $self = shift;
  if ( !exists $self->{'ContigInfo'} ){
	 my $ad=Bio::Vega::DBSQL::ContigInfoAdaptor->new($self);
	 $self->{'ContigInfo'}=$ad;
  }
  return $self->{'ContigInfo'};
}

sub get_AuthorAdaptor {
  my $self = shift;
  if ( !exists $self->{'Author'} ){
	 my $ad=Bio::Vega::DBSQL::AuthorAdaptor->new($self);
	 $self->{'Author'}=$ad;
  }
  return $self->{'Author'};
}

sub get_AuthorGroupAdaptor {
  my $self = shift;
  if ( !exists $self->{'AuthorGroup'} ){
	 my $ad=Bio::Vega::DBSQL::AuthorGroupAdaptor->new($self);
	 $self->{'AuthorGroup'}=$ad;
  }
  return $self->{'AuthorGroup'};
}

sub get_AttributeAdaptor {
  my $self = shift;
  if ( !exists $self->{'ContigAttribute'} ){
	 my $ad=Bio::Vega::DBSQL::AttributeAdaptor->new($self);
	 $self->{'ContigAttribute'}=$ad;
  }
  return $self->{'ContigAttribute'};
}

sub get_StableIdAdaptor {
  my $self = shift;
  if ( !exists $self->{'StableId'} ){
	 my $ad=Bio::Vega::DBSQL::StableIdAdaptor->new($self);
	 $self->{'StableId'}=$ad;
  }
  return $self->{'StableId'};
}

sub get_ExonAdaptor {
  my $self = shift;
  if ( !exists $self->{'VegaExon'} ){
	 my $ad=Bio::Vega::DBSQL::ExonAdaptor->new($self);
	 $self->{'VegaExon'}=$ad;
  }
  return $self->{'VegaExon'};
}

sub get_TranscriptAdaptor {
  my $self = shift;
  if ( !exists $self->{'VegaTranscript'} ){
	 my $ad=Bio::Vega::DBSQL::TranscriptAdaptor->new($self);
	 $self->{'VegaTranscript'}=$ad;
  }
  return $self->{'VegaTranscript'};
}

# We now rebless Translation inside Bio::Vega::Transcript::reincarnate_transcript() instead
#sub get_TranslationAdaptor {
#  my $self = shift;
#  if ( !exists $self->{'VegaTranslation'} ){
#     my $ad=Bio::Vega::DBSQL::TranslationAdaptor->new($self);
#     $self->{'VegaTranslation'}=$ad;
#  }
#  return $self->{'VegaTranslation'};
#}

sub get_AssemblyTagAdaptor {
  my $self = shift;
  if ( !exists $self->{'AssemblyTag'} ){
	 my $ad=Bio::Vega::DBSQL::AssemblyTagAdaptor->new($self);
	 $self->{'AssemblyTag'}=$ad;
  }
  return $self->{'AssemblyTag'};
}

sub get_ContigLockAdaptor {
  my $self = shift;
  if ( !exists $self->{'ContigLock'} ){
	 my $ad=Bio::Vega::DBSQL::ContigLockAdaptor->new($self);
	 $self->{'ContigLock'}=$ad;
  }
  return $self->{'ContigLock'};
}

sub get_MetaContainer {
  my( $self ) = @_;
  if ( !exists $self->{'VegaMetaContainer'} ){
	 $self->{'VegaMetaContainer'}=Bio::Vega::DBSQL::MetaContainer->new($self);
  }
  return $self->{'VegaMetaContainer'};
}

sub get_AnnotationBroker {
  my( $self ) = @_;
  if ( !exists $self->{'AnnotationBroker'} ){
	 $self->{'AnnotationBroker'}=Bio::Vega::AnnotationBroker->new($self);
  }
  return $self->{'AnnotationBroker'};
}

sub begin_work {
  my $self = shift;
  $self->dbc->db_handle->{AutoCommit}=0;
  $self->dbc->do('BEGIN');
}

sub commit {
  my $self = shift;
  $self->dbc->do('COMMIT');
}

sub rollback {
  my $self = shift;
  $self->dbc->do('ROLLBACK');
}


sub rollback_to_savepoint {
  my ($self,$savepoint) = @_;
  unless ($savepoint){
	 $savepoint='x';
  }
  $self->dbc->do('ROLLBACK TO SAVEPOINT '.$savepoint);
}

sub savepoint {
  my ($self,$savepoint) = @_;
  unless ($savepoint){
	 $savepoint='x';
  }
  $self->dbc->do('SAVEPOINT '.$savepoint);
}

sub check_for_transaction{
  my $self=shift;
  my $dbh=$self->dbc->db_handle;
  return $dbh->{AutoCommit};
}


1;
__END__

=head1 NAME - Bio::Vega::DBSQL::DBAdaptor.pm

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk
