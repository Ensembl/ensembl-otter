package Bio::Otter::DBSQL::AuthorAdaptor;

use strict;
use Carp;
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

    my $author_name = $author->name  or confess "Author doesn't have a name";
    my $autor_email = $author->email or confess "Author does not have an email address";

    # Is this author already in the database?
    my $get_db_id = $self->prepare(q{
        SELECT author_id
        FROM author
        WHERE author_name = ?
        });
    $get_db_id->execute($author_name);
    my ($db_id) = $get_db_id->fetchrow;
    $get_db_id->finish;

    if ($db_id) {
	$author->dbID($db_id);
	return 1;
    }

    # Insert new author entry
    my $sth = $self->prepare(q{
        INSERT INTO author(author_id
              , author_email
              , author_name)
        VALUES (NULL,?,?)
        });
    $sth->execute($author_email, $author_name);
    $db_id = $sth->{'mysql_insertid'}
        or $self->throw('Failed to get autoincremented ID from statement handle');
    $author->dbID($db_id);
}

1;

	





