package Bio::Otter::DBSQL::TranscriptClassAdaptor;

use strict;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::TranscriptClass;

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
		SELECT transcript_class_id,
		       name,
		       description
		FROM transcript_class }
	. $where_clause;

	my $sth = $self->prepare($sql);
	$sth->execute;

	if (my $ref = $sth->fetchrow_hashref) {
	    my $obj = new Bio::Otter::TranscriptClass();
	    $obj->dbID($ref->{transcript_class_id});
	    $obj->name($ref->{name});
	    $obj->description($ref->{description});
		
	    return $obj;

	} else {
		return;
	}
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
		$self->throw("Id must be entered to fetch a TranscriptClass object");
	}

	my $obj = $self->_generic_sql_fetch("where transcript_class_id = $id");

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


sub fetch_by_name {
	my ($self,$name) = @_;

	if (!defined($name)) {
		$self->throw("Name must be entered to fetch a TranscriptClass object");
	}

	my $obj = $self->_generic_sql_fetch("where name = \'$name\'");

	return $obj;
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
		$self->throw("Must provide a TranscriptClass object to the store method");
	} elsif (! $obj->isa("Bio::Otter::TranscriptClass")) {
		$self->throw("Argument must be an TranscriptClass object to the store method.  Currently is [$obj]");
	}

	my $tmp = $self->exists($obj);

	if (defined($tmp)) {
	    $obj->dbID($tmp->dbID);
	    return;
	}
    ### Added to intercept MIT_OLD2: prefix bug:
    else {
        $self->throw(sprintf "No such transcript class '%s'", $obj->name);
    }
    
	my $name = "";

	my $desc = "";

	if (defined($obj->name)) {
	    $name = $obj->name;
	}
	if (defined($obj->description)) {
	    $desc = $obj->description;
	}

	my $sql = "insert into transcript_class(transcript_class_id,name,description) values (null,\'" . 
	    $name . "\',\'".
	    $desc . "\')";

	my $sth = $self->prepare($sql);
	my $rv = $sth->execute();

	$self->throw("Failed to insert TranscriptClass " . $obj->name) unless $rv;

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
		$self->throw("Must provide a TranscriptClass object to the exists method");
	} elsif (! $obj->isa("Bio::Otter::TranscriptClass")) {
		$self->throw("Argument must be a TranscriptClass object to the exists method.  Currently is [$obj]");
	}

	if (!defined($obj->name)) {
	    $self->throw("Can't check if a TranscriptClass object exists without a name");
	}

	my $newobj = $self->_generic_sql_fetch("where name = \'" .   $obj->name . "\'");

	return $newobj;

}
1;

	





