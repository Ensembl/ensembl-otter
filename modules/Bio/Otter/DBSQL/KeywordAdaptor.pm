package Bio::Otter::DBSQL::KeywordAdaptor;

use strict;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::Keyword;

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
		SELECT k.keyword_id,
		       k.keyword_name,
                       ck.clone_info_id
		FROM keyword k,clone_info_keyword ck }
	. $where_clause;

	#print $sql . "\n";

	my $sth = $self->prepare($sql);
	$sth->execute;

	my @obj;

	while (my $ref = $sth->fetchrow_hashref) {
	    my $obj = new Bio::Otter::Keyword;
	    $obj->dbID           ($ref->{'keyword_id'});
	    $obj->name           ($ref->{'keyword_name'});
	    $obj->clone_info_id  ($ref->{'clone_info_id'});
	    
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
	$self->throw("Id must be entered to fetch a keyword object");
    }
    
    my @obj = $self->_generic_sql_fetch("where ck.keyword_id = k.keyword_id and k.keyword_id = $id");
    
    return @obj;
}

sub list_by_clone_info_id {
    my ($self,$id) = @_;
    
    if (!defined($id)) {
	$self->throw("Id must be entered to fetch a keyword object");
    }
    
    my @obj = $self->_generic_sql_fetch("where ck.keyword_id = k.keyword_id and ck.clone_info_id = $id");
    
    return @obj;
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
	$self->throw("Name must be entered to fetch keyword objects");
    }
    
    my @obj = $self->_generic_sql_fetch("where ck.keyword_id = k.keyword_id and k.keyword_name = \'$name\'");
    
    return @obj;
}

sub get_all_Keyword_names {
    my ($self) = @_;

    my $sql = "SELECT distinct keyword_name from keyword";

    my $sth = $self->prepare($sql);
    $sth->execute;

    my @names;

    while (my $ref = $sth->fetchrow_hashref) {
	push(@names,$ref->{keyword_name});
    }

    return @names;
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
	
    while (my $keyword = shift @_) {
	if (!defined($keyword)) {
	    $self->throw("Must provide a keyword object to the store method");
	} elsif (! $keyword->isa("Bio::Otter::Keyword")) {
	    $self->throw("Argument must be a keyword object to the store method.  Currently is [$keyword]");
	}

	if (!defined($keyword->clone_info_id)) {
	    $self->throw("Must provide a clone_info_id value to the keyword object when trying to store");
	}
	
	my $tmpkey = $self->exists($keyword);
	
	if (defined($tmpkey)) {
	    $keyword->dbID($tmpkey->dbID);

	    if (defined($tmpkey->clone_info_id)) {
		$keyword->clone_info_id($tmpkey->clone_info_id);
		return;
	    }
	}
	
	if (!defined($keyword->dbID)) {

	    my $sql = "insert into keyword(keyword_id,keyword_name) values (null,\'" . 
		$keyword->name . "\')";
	    
	    my $sth = $self->prepare($sql);
	    my $rv = $sth->execute();
	    
	    $self->throw("Failed to insert keyword " . $keyword->name) unless $rv;
	    
	    $sth = $self->prepare("select last_insert_id()");
	    my $res = $sth->execute;
	    my $row = $sth->fetchrow_hashref;
	    $sth->finish;
	
	    $keyword->dbID($row->{'last_insert_id()'});
	}
	
	# Now the clone bit

	my $sql2 = "insert into clone_info_keyword(clone_info_id,keyword_id) values(" .
	    $keyword->clone_info_id . "," . 
	    $keyword->dbID . ")";

	my $sth2 = $self->prepare($sql2);
	my $rv2  = $sth2->execute;
	
	$self->throw("Failed to insert keyword ". $keyword->name . " for clone_info " . $keyword->clone_info_id) unless $rv2;
	
	$sth2->finish;
	
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
    my ($self,$keyword) = @_;

    if (!defined($keyword)) {
	$self->throw("Must provide a keyword object to the exists method");
    } elsif (! $keyword->isa("Bio::Otter::Keyword")) {
	$self->throw("Argument must be a keyword object to the exists method.  Currently is [$keyword]");
    }

    if (!defined($keyword->name)) {
	$self->throw("Can't check if a keyword exists without a name");
    }

    my $sql = "select * from keyword where keyword_name = \'"  . $keyword->name . "\'";

    my $sth = $self->prepare($sql);
    my $rv  = $sth->execute;

    $self->throw("Could not check if keyword " . $keyword->name . " exists") unless $rv;

    my $newkey = new Bio::Otter::Keyword(-name => $keyword->name);

    if (my $ref = $sth->fetchrow_hashref) {
	
	my $dbid = $ref->{keyword_id};

	$newkey->dbID($dbid);

    } else {
	return $newkey;
    }
    
    if (defined($keyword->clone_info_id)) {
	my $sql2 = "select * from clone_info_keyword where keyword_id = " . $newkey->dbID . " and clone_info_id = " . $keyword->clone_info_id;
	my $sth2 = $self->prepare($sql2);
	my $rv2  = $sth2->execute;

	$self->throw("Can't find link between keyword and clone_info for keyword " . $keyword->name . " and info " . $keyword->clone_info_id) unless $rv2;

	if (my $ref = $sth2->fetchrow_hashref) {
	    my $clone_info_id = $ref->{clone_info_id};
	    $newkey->clone_info_id($clone_info_id);
	}
    }

    return $newkey;
    
}

1;

	





