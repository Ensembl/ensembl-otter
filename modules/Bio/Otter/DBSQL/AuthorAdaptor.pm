package Bio::Otter::DBSQL::AuthorAdaptor;

use strict;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::Author;

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
		SELECT author_id,
		       author_email,
		       author_name
		FROM author }
	. $where_clause;

	my $sth = $self->prepare($sql);
	$sth->execute;

	if (my $ref = $sth->fetchrow_hashref) {
		my $author = new Bio::Otter::Author;
		$author->dbID($ref->{author_id});
		$author->email($ref->{author_email});
		$author->name($ref->{author_name});
		
		return $author;

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
		$self->throw("Id must be entered to fetch an author object");
	}

	my $author = $self->_generic_sql_fetch("where author_id = $id");

	return $author;
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
		$self->throw("Name must be entered to fetch an author object");
	}

	my $author = $self->_generic_sql_fetch("where author_name = \'$name\'");

	return $author;
}

=head2 fetch_by_email

 Title   : fetch_by_email
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_email {
	my ($self,$email) = @_;

	if (!defined($email)) {
		$self->throw("Email address must be entered to fetch an author object");
	}

	my $author = $self->_generic_sql_fetch("where author_email= \'$email\'");

	return $author;
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
	my ($self,$author) = @_;

	if (!defined($author)) {
		$self->throw("Must provide an author object to the store method");
	} elsif (! $author->isa("Bio::Otter::Author")) {
		$self->throw("Argument must be an author object to the store method.  Currently is [$author]");
	}

	my $tmpauth = $self->exists($author);

	if (defined($tmpauth)) {
		$author->dbID($tmpauth->dbID);
		return;
	}

	my $sql = "insert into author(author_id,author_email,author_name) values (null,\'" . 
		$author->email . "\',\'".
		$author->name . "\')";

  my $sth = $self->prepare($sql);
	my $rv = $sth->execute();

	$self->throw("Failed to insert author " . $author->name) unless $rv;

	$sth = $self->prepare("select last_insert_id()");
	my $res = $sth->execute;
	my $row = $sth->fetchrow_hashref;
	$sth->finish;
	
	$author->dbID($row->{'last_insert_id()'});
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
	my ($self,$author) = @_;

	if (!defined($author)) {
		$self->throw("Must provide an author object to the exists method");
	} elsif (! $author->isa("Bio::Otter::Author")) {
		$self->throw("Argument must be an author object to the exists method.  Currently is [$author]");
	}

	if (!defined($author->name)) {
		$self->throw("Can't check if an author exists without a name");
	}
	if (!defined($author->email)) {
		$self->throw("Can't check if an author exists without an email address");
	}

	my $newauthor = $self->_generic_sql_fetch("where author_name = \'" .   $author->name .
																				 "\' and author_email = \'" . $author->email . "\'");

	return $newauthor;

}
1;

	





