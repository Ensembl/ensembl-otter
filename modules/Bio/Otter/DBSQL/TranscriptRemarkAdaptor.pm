package Bio::Otter::DBSQL::TranscriptRemarkAdaptor;

use strict;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::TranscriptRemark;

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
		SELECT transcript_remark_id,
		       remark,
		       transcript_info_id 
		FROM transcript_remark }
	. $where_clause;

	my $sth = $self->prepare($sql);
	$sth->execute;

	my @remark;

	while (my $ref = $sth->fetchrow_hashref) {
	    my $remark = new Bio::Otter::TranscriptRemark;
	    $remark->dbID($ref->{transcript_remark_id});
	    $remark->remark($ref->{remark});
	    $remark->transcript_info_id($ref->{transcript_info_id});
		
	    push(@remark,$remark);

	}

	return @remark;
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
		$self->throw("Id must be entered to fetch a TranscriptRemark object");
	}

	my @remark = $self->_generic_sql_fetch("where transcript_remark_id = $id");

	# Not sure about this
	if (scalar(@remark) == 1) {
	    return $remark[0];
	}
}

=head2 list_by_TranscriptInfo_id

 Title   : list_by_TranscriptInfo_id
 Usage   : $obj->list_by_TranscriptInfo_id($newval)
 Function: 
 Example : 
 Returns : value of list_by_TranscriptInfo_id
 Args    : newvalue (optional)


=cut

sub list_by_transcript_info_id {
   my ($self,$id) = @_;

   if (!defined($id)) {
       $self->throw("TranscriptInfo id must be entered to fetch a TranscriptRemark object");
   }

   my @remark = $self->_generic_sql_fetch("where transcript_info_id = $id");

   return @remark;
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
    my $self = shift @_;

    while (my $remark = shift @_) {
	if (!defined($remark)) {
		$self->throw("Must provide a TranscriptRemark object to the store method");
	} elsif (! $remark->isa("Bio::Otter::TranscriptRemark")) {
		$self->throw("Argument must be a TranscriptRemark object to the store method.  Currently is [$remark]");
	}

	my $tmp = $self->exists($remark);

	if ($tmp) { 
   	   $remark->dbID($tmp->dbID);
	   return;
	}

        my $quoted_remark = $self->db->db_handle->quote($remark->remark);
        my $sql = "insert into transcript_remark(transcript_remark_id,remark,transcript_info_id) values (null," .
                        $quoted_remark . "," .
                        $remark->transcript_info_id . ")";

#	my $sql = "insert into transcript_remark(transcript_remark_id,remark,transcript_info_id) values (null,\'" . 
#		$remark->remark . "\',".
#		$remark->transcript_info_id . ")";

	my $sth = $self->prepare($sql);
	my $rv = $sth->execute();

	$self->throw("Failed to insert transcript remark " . $remark->remark) unless $rv;

	$sth = $self->prepare("select last_insert_id()");
	my $res = $sth->execute;
	my $row = $sth->fetchrow_hashref;
	$sth->finish;
	
	$remark->dbID($row->{'last_insert_id()'});
    }
    return 1;
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
	my ($self,$remark) = @_;

	if (!defined($remark)) {
		$self->throw("Must provide a TranscriptRemark object to the exists method");
	} elsif (! $remark->isa("Bio::Otter::TranscriptRemark")) {
		$self->throw("Argument must be an TranscriptRemark object to the exists method.  Currently is [$remark]");
	}

	if (!defined($remark->remark)) {
		$self->throw("Can't check if a transcript remark exists without remark text");
	}
	if (!defined($remark->transcript_info_id)) {
		$self->throw("Can't check if a transcript remark exists without a transcript info id");
	}

        my $quoted_remark = $self->db->db_handle->quote($remark->remark);
	my @newremark = $self->_generic_sql_fetch("where remark = " .   $quoted_remark .
						 " and transcript_info_id = " . $remark->transcript_info_id);

        if (scalar(@newremark) > 0) {
	   return $newremark[0];
        } else {
           return "";
        }
}

1;

	





