package Bio::Otter::DBSQL::EvidenceAdaptor;

use strict;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::EnsEMBL::DBEntry;
use Bio::Otter::Evidence;

use vars qw(@ISA);

@ISA = qw ( Bio::EnsEMBL::DBSQL::BaseAdaptor);

# new is inherieted

=head2 _generic_sql_fetch

 Title   : _generic_sql_fetch
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub _generic_sql_fetch {
	my( $self, $where_clause ) = @_;

	my $sql = q{
		SELECT evidence_id,
                       evidence_name,
		       transcript_info_id,
		       type
		FROM evidence }
	. $where_clause;

	my $sth = $self->prepare($sql);
	$sth->execute;

	my @obj;

	while (my $ref = $sth->fetchrow_hashref) {
	    my $obj = new Bio::Otter::Evidence;
	    $obj->dbID($ref->{evidence_id});
	    $obj->name($ref->{evidence_name});
	    $obj->transcript_info_id($ref->{transcript_info_id});
	    $obj->type($ref->{type});
		
	    push(@obj,$obj);

	}
	return @obj;
}

=head2 fetch_by_dbID

 Title   : fetch_by_dbID
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_dbID {
	my ($self,$id) = @_;

	if (!defined($id)) {
		$self->throw("Id must be entered to fetch an Evidence object");
	}

	my ($obj) = $self->_generic_sql_fetch("where evidence_id = $id");

	return $obj;
}


=head2 list_by_transcript_info_id

 Title   : list_by_transcript_info_id
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub list_by_transcript_info_id{
   my ($self,$id) = @_;

   if (!defined($id)) {
       $self->throw("Transcript id must be entered to fetch an Evidence object");
   }
   
   my @evidence = $self->_generic_sql_fetch("where transcript_info_id = \'$id\'");

   return @evidence;


}

=head2 list_by_type

 Title   : list_by_type
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub list_by_type{
   my ($self,$type) = @_;

   if (!defined($type)) {
       $self->throw("Type must be entered to fetch an Evidence object");
   }
   
   my @obj = $self->_generic_sql_fetch("where type = \'$type\'");

   return @obj;


}

=head2 store

 Title   : store
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub store {
    my ($self,@obj) = @_;

    foreach my $obj (@obj) {
    if (!defined($obj)) {
	$self->throw("Must provide an Evidenceobject to the store method");
    } elsif (! $obj->isa("Bio::Otter::Evidence")) {
	$self->throw("Argument must be a Evidence object to the store method.  Currently is [$obj]");
    }

    my $dbea = $self->db->get_DBEntryAdaptor;

    my $tmp = $self->exists($obj);


    if (defined($tmp)) {
	$obj->dbID($tmp->dbID);
	return;
    }

    my $sql = "insert into evidence(evidence_id,evidence_name,transcript_info_id,type) values (null,\'" . $obj->name . "\'," . 
	$obj->transcript_info_id . ",\'".
	$obj->type . "\')";

    my $sth = $self->prepare($sql);
    my $rv = $sth->execute();

    $self->throw("Failed to insert evidence for transcript  " . $obj->transcript_info_id) unless $rv;

    $sth = $self->prepare("select last_insert_id()");
    my $res = $sth->execute;
    my $row = $sth->fetchrow_hashref;
    $sth->finish;

    $obj->dbID($row->{'last_insert_id()'});
  }
}

=head2 exists

 Title   : exists
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub exists {
    my ($self,$obj) = @_;

    if (!defined($obj)) {
	$self->throw("Must provide an Evidence object to the exists method");
    } elsif (! $obj->isa("Bio::Otter::Evidence")) {
	$self->throw("Argument must be an Evidence object to the exists method.  Currently is [$obj]");
    }

    if (!defined($obj->transcript_info_id)) {
	$self->throw("Can't check if an Evidence exists without a transcript info id");
    }

    if (!defined($obj->type)) {
	$self->throw("Can't check if an Evidence exists without a type");
    }

    my ($newobj) = $self->_generic_sql_fetch("where transcript_info_id = " . $obj->transcript_info_id . " and evidence_name = \'" . $obj->name . "\'" .
					     " and type = \'" . $obj->type . "\'");


    return $newobj;

}
1;

	





