package Bio::Otter::DBSQL::GeneSynonymAdaptor;

use strict;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;

use Bio::Otter::GeneSynonym;

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
		SELECT synonym_id,
		       name,
		       gene_info_id
		FROM gene_synonym }
	. $where_clause
        . q{ ORDER BY synonym_id };

	my $sth = $self->prepare($sql);
	$sth->execute;

	my @out;

	while  (my $ref = $sth->fetchrow_hashref) {

	    my $obj = new Bio::Otter::GeneSynonym;
	    eval {
		$obj->dbID($ref->{synonym_id});
	        $obj->name($ref->{name});
	        $obj->gene_info_id($ref->{gene_info_id});
	    };
	    if ($@){
	      warn "No dbID: can't fetch synonym_id";
              warn "Can't fetch name";
	      warn "Cant' fetch gene info";
            }
	    push(@out,$obj);
	  }
	return @out;

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
		$self->throw("Id must be entered to fetch a GeneSynonym object");
	}

	my ($obj) = $self->_generic_sql_fetch("where synonym_id = $id");

	return $obj;
}

=head2 fetch_by_name

 Title   : fetch_by_name
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut


sub list_by_name {
	my ($self,$name) = @_;

	if (!defined($name)) {
		$self->throw("Name must be entered to fetch a GeneSynonym object");
	}

	my @obj = $self->_generic_sql_fetch("where name = \'$name\'");

	return @obj;
}


=head2 fetch_by_gene_info_id

 Title   : fetch_by_gene_info_id
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub list_by_gene_info_id{
   my ($self,$id) = @_;

   if (!defined($id)) {
       $self->throw("GeneInfo id must be entered to fetch a GeneName object");
	}

   my @obj = $self->_generic_sql_fetch("where gene_info_id = $id");
   return @obj;

}

sub fetch_all {
  my ($self) = @_;

  my @obj = $self->_generic_sql_fetch;;

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
    my ($self,$obj) = @_;

    if (!defined($obj)) {
	$self->throw("Must provide a GeneSynonym object to the store method");
    } elsif (! $obj->isa("Bio::Otter::GeneSynonym")) {
	$self->throw("Argument must be a GeneSynonym object to the store method.  Currently is [$obj]");
	}

    my $tmp = $self->exists($obj);

    if (defined($tmp)) {
	$obj->dbID($tmp->dbID);
	return;
    }

    my $sql = "insert into gene_synonym(synonym_id,name,gene_info_id) values (null,\'" . 
	$obj->name . "\',".
	$obj->gene_info_id . ")";

    my $sth = $self->prepare($sql);
    my $rv = $sth->execute();

    $self->throw("Failed to insert synonym_name " . $obj->name) unless $rv;

    $sth = $self->prepare("select last_insert_id()");
    my $res = $sth->execute;
    my $row = $sth->fetchrow_hashref;
    $sth->finish;
	
    $obj->dbID($row->{'last_insert_id()'});
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
	$self->throw("Must provide a GeneSynonym object to the exists method");
    } elsif (! $obj->isa("Bio::Otter::GeneSynonym")) {
	$self->throw("Argument must be a GeneSynonym object to the exists method.  Currently is [$obj]");
    }

    if (!defined($obj->name)) {
	$self->throw("Can't check if a GeneSynonym exists without a name");
    }
    if (!defined($obj->gene_info_id)) {
	$self->throw("Can't check if a GeneSynonym exists without a GeneInfo id");
    }

    my ($newobj) = $self->_generic_sql_fetch("where name = \'"        . $obj->name .
					   "\' and gene_info_id = " . $obj->gene_info_id);

    return $newobj;

}

1;

	





