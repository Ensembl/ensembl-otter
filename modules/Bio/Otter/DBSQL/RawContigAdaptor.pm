package Bio::Otter::DBSQL::RawContigAdaptor;

use strict;

use Bio::EnsEMBL::DBSQL::RawContigAdaptor;

use vars qw(@ISA);

@ISA = qw ( Bio::EnsEMBL::DBSQL::RawContigAdaptor);


# This is assuming the otter info and the ensembl genes are in the same database 
# and so have the same adaptor

sub new {
    my ($class,$dbobj) = @_;

    my $self = {};
    bless $self,$class;

    if( !defined $dbobj || !ref $dbobj ) {
        $self->throw("Don't have a db [$dbobj] for new adaptor");
    }

    $self->db($dbobj);

    return $self;
}


# Need to override fetch_filled_by_dbIDs in Bio::EnsEMBL::DBSQL::RawContigAdaptor
# because it makes Clones without going throught the CloneAdaptor

sub fetch_filled_by_dbIDs {
   my ($self,@ids) = @_;

   my $result = $self->SUPER::fetch_filled_by_dbIDs(@ids);

   foreach my $key (keys %$result) {
      my $clone = $result->{$key}->clone;

      $clone = $self->db->get_CloneAdaptor->annotate_clone($clone);  

   }

   return $result;
}


1;

	





