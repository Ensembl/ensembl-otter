package Bio::Otter::DBSQL::DBAdaptor;

use Bio::EnsEMBL::DBSQL::DBAdaptor;

@ISA = qw ( Bio::EnsEMBL::DBSQL::DBAdaptor);

sub new {
  my ($class,@args) = @_;

  my $self = $class->SUPER::new(@args);

  my ($dataset)  = $self->_rearrange([qw(DATASET)],@args);

  $self->dataset($dataset) if $dataset;

  return $self;
}

sub dataset {
  my ($self,$dataset) = @_;

  if (defined($dataset)) {
    $self->{_dataset} = $dataset;
  }

  return  $self->{_dataset};
}

sub begin_work {
    my $self = shift;

    $self->db_handle->begin_work();
}

sub commit {
    my $self = shift;

    $self->db_handle->commit();
}

sub rollback {
    my $self = shift;

    $self->db_handle->rollback();
}


# These next methods override the methods in the core
# Ensembl DBAdaptor, returning the otter Annotated versions
# of the core adaptors, so that all clones, genes and transcripts
# that come out of an Otter DBAdaptor have the extra annotation
# information
sub get_RawContigAdaptor {
  my $self = shift;

  return $self->_get_adaptor("Bio::Otter::DBSQL::RawContigAdaptor");
}
sub get_CloneAdaptor {
  my $self = shift;

  return
    $self->_get_adaptor("Bio::Otter::DBSQL::AnnotatedCloneAdaptor");
} 
sub get_GeneAdaptor {
  my $self = shift;

  return
    $self->_get_adaptor("Bio::Otter::DBSQL::AnnotatedGeneAdaptor");
} 
sub get_TranscriptAdaptor {
  my $self = shift;

  return
    $self->_get_adaptor("Bio::Otter::DBSQL::AnnotatedTranscriptAdaptor");
} 

sub get_AuthorAdaptor {
  my $self = shift;

  return
    $self->_get_adaptor("Bio::Otter::DBSQL::AuthorAdaptor");
} 

sub get_CloneInfoAdaptor {
  my $self = shift;

  return
     $self->_get_adaptor("Bio::Otter::DBSQL::CloneInfoAdaptor");
}

sub get_CloneLockAdaptor {
  my $self = shift;

  return
     $self->_get_adaptor("Bio::Otter::DBSQL::CloneLockAdaptor");
}

sub get_EvidenceAdaptor {
  my $self = shift;

  return
     $self->_get_adaptor("Bio::Otter::DBSQL::EvidenceAdaptor");
}

sub get_GeneInfoAdaptor {
  my $self = shift;

  return
     $self->_get_adaptor("Bio::Otter::DBSQL::GeneInfoAdaptor");
}

sub get_GeneNameAdaptor {
  my $self = shift;

  return
     $self->_get_adaptor("Bio::Otter::DBSQL::GeneNameAdaptor");
}

sub get_GeneSynonymAdaptor {
  my $self = shift;

  return
     $self->_get_adaptor("Bio::Otter::DBSQL::GeneSynonymAdaptor");
}

sub get_GeneRemarkAdaptor {
  my $self = shift;

  return
     $self->_get_adaptor("Bio::Otter::DBSQL::GeneRemarkAdaptor");
}

sub get_TranscriptClassAdaptor {
  my $self = shift;

  return
     $self->_get_adaptor("Bio::Otter::DBSQL::TranscriptClassAdaptor");
}

sub get_TranscriptInfoAdaptor {
  my $self = shift;

  return
     $self->_get_adaptor("Bio::Otter::DBSQL::TranscriptInfoAdaptor");
}

sub get_TranscriptRemarkAdaptor {
  my $self = shift;

  return
     $self->_get_adaptor("Bio::Otter::DBSQL::TranscriptRemarkAdaptor");
}

sub get_KeywordAdaptor {
    my $self = shift;

    return $self->_get_adaptor("Bio::Otter::DBSQL::KeywordAdaptor");
}

sub get_CurrentGeneInfoAdaptor {
    my $self = shift;

    return $self->_get_adaptor("Bio::Otter::DBSQL::CurrentGeneInfoAdaptor");
}
sub get_CurrentTranscriptInfoAdaptor {
    my $self = shift;

    return $self->_get_adaptor("Bio::Otter::DBSQL::CurrentTranscriptInfoAdaptor");
}

sub get_StableIdAdaptor {
    my $self = shift;

    return $self->_get_adaptor("Bio::Otter::DBSQL::StableIdAdaptor");
}
sub get_CloneRemarkAdaptor {
    my $self = shift;

    return $self->_get_adaptor("Bio::Otter::DBSQL::CloneRemarkAdaptor");
}

sub get_MetaContainer {
    my( $self ) = @_;
    
    my( $mc );
    unless ($mc = $self->{'_meta_container'}) {
        require Bio::Otter::DBSQL::MetaContainer;
        $mc = Bio::Otter::DBSQL::MetaContainer->new($self);
        $self->{'_meta_container'} = $mc;
    }
    return $mc;
}

1;
