package Bio::Otter::DBSQL::GeneRemarkAdaptor;

use strict;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::GeneRemark;

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
		SELECT gene_remark_id,
		       remark,
		       gene_info_id 
		FROM gene_remark }
	. $where_clause
        . q{ ORDER BY gene_remark_id };

	my $sth = $self->prepare($sql);
	$sth->execute;

	my @remark;

	while (my ($rem_id, $txt, $giid) = $sth->fetchrow) {
	    my $remark = new Bio::Otter::GeneRemark;
	    $remark->dbID($rem_id);
	    $remark->remark($txt);
	    $remark->gene_info_id($giid);
		
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
		$self->throw("Id must be entered to fetch a GeneRemark object");
	}

	my @remark = $self->_generic_sql_fetch("where gene_remark_id = $id");

	# Not sure about this
	if (scalar(@remark) == 1) {
	    return $remark[0];
	}
}

=head2 list_by_gene_info_id

 Title   : list_by_GeneInfo_id
 Usage   : $obj->list_by_GeneInfo_id($newval)
 Function: 
 Example : 
 Returns : value of list_by_GeneInfo_id
 Args    : newvalue (optional)


=cut

sub list_by_gene_info_id {
   my ($self,$id) = @_;

   if (!defined($id)) {
       $self->throw("GeneInfo id must be entered to fetch a GeneRemark object");
   }

   my @remark = $self->_generic_sql_fetch("where gene_info_id = $id");

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
    my $self = shift;

     while (my $remark = shift @_) {
	if (!defined($remark)) {
		$self->throw("Must provide a GeneRemark object to the store method");
	} elsif (! $remark->isa("Bio::Otter::GeneRemark")) {
		$self->throw("Argument must be a GeneRemark object to the store method.  Currently is [$remark]");
	}

	my $tmp = $self->exists($remark);

	if ($tmp) { 
   	   $remark->dbID($tmp->dbID);
	   return;
	}

	my $sth = $self->prepare(q{
            INSERT INTO gene_remark(remark
                  , gene_info_id)
            VALUES (?,?)
            });
	$sth->execute($remark->remark, $remark->gene_info_id);
	
	$remark->dbID($sth->{'mysql_insertid'});
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
		$self->throw("Must provide a GeneRemark object to the exists method");
	} elsif (! $remark->isa("Bio::Otter::GeneRemark")) {
		$self->throw("Argument must be an GeneRemark object to the exists method.  Currently is [$remark]");
	}

	if (!defined($remark->remark)) {
		$self->throw("Can't check if a gene remark exists without remark text");
	}
	if (!defined($remark->gene_info_id)) {
		$self->throw("Can't check if a gene remark exists without a gene info id");
	}

        my $quoted_remark = $self->db->db_handle->quote($remark->remark);
	my @newremark = $self->_generic_sql_fetch("where remark = ".   $quoted_remark .
						 " and gene_info_id = " . $remark->gene_info_id);

        if (scalar(@newremark) > 0) {
	   return $newremark[0];
        } else {
           return "";
        }
}

1;

	





