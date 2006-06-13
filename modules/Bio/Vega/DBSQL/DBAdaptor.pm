package Bio::Vega::DBSQL::DBAdaptor;

use Bio::Vega::DBSQL::ContigInfoAdaptor;
use Bio::Vega::DBSQL::AuthorAdaptor;
use Bio::Vega::DBSQL::AuthorGroupAdaptor;
use Bio::Vega::DBSQL::AttributeAdaptor;

use base 'Bio::EnsEMBL::DBSQL::DBAdaptor';


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

sub begin_work {
    my $self = shift;
    $self->dbc->db_handle->do('BEGIN');
}

sub commit {
    my $self = shift;
    $self->dbc->db_handle->do('COMMIT');
}

sub rollback {
    my $self = shift;
    $self->dbc->db_handle->do('ROLLBACK');
}

1;
__END__

=head1 NAME - Bio::Vega::DBSQL::DBAdaptor.pm

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk
