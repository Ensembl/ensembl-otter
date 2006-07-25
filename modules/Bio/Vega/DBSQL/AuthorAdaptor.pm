package Bio::Vega::DBSQL::AuthorAdaptor;

use strict;
use Bio::Vega::Author;
use Bio::EnsEMBL::Utils::Exception qw ( throw warning );

use base 'Bio::EnsEMBL::DBSQL::BaseAdaptor';


=head2 _generic_sql_fetch

 Title   : _generic_sql_fetch
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub _generic_sql_fetch {
  my( $self, $where_clause,$author ) = @_;
  if (! defined $author ){
	 $author=new Bio::Vega::Author;
  }
  my $sql = "
             SELECT a.author_id as author_id,
                    a.author_email as author_email,
                    a.author_name as author_name,
                    g.group_id as group_id,
                    g.group_name as group_name,
                    g.group_email as group_email
	          FROM author a,author_group g "
	          .$where_clause.
		       " AND a.group_id=g.group_id ";

  my $sth = $self->prepare($sql);
  $sth->execute();

  if (my $ref = $sth->fetchrow_hashref) {
         $author->dbID($ref->{author_id});
         $author->email($ref->{author_email});
         $author->name($ref->{author_name});
         if (! defined $author->group){
           my $group=new Bio::Otter::AuthorGroup;
           $author->group($group);
         }
         $author->group->dbID($ref->{group_id});
         $author->group->name($ref->{group_name});
         $author->group->email($ref->{group_email});
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

	my $author = $self->_generic_sql_fetch(" where author_id = $id ");

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
	
sub exists_in_db {
  my ($self,$author) = @_;
  if (!defined($author->name)) {
	 throw("Name is empty in the author object - should be set to check for exsistence");
  }
  if (!defined($author->email)) {
	 throw("email is empty in the author object - should be set to check for exsistence");
  }
  my $author_email=$author->email;
  my $author_name=$author->name;
  $author = $self->_generic_sql_fetch("where author_email= \'$author_email\' and author_name=\'$author_name\' ",$author);
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
	 throw("Must provide an author object to the store method");
  } elsif (! $author->isa("Bio::Vega::Author")) {
	 throw("Argument must be an author object to the store method.  Currently is [$author]");
  }
  my $author_name  = $author->name  || throw "Author does not have a name";
  my $author_email = $author->email || throw "Author does not have an email address";
  # Is this author already in the database?

  if ( $self->exists_in_db($author)){
	 return 1;
  }
  my $group=$author->group;
  my $group_id=$group->dbID;
  my $group_name=$group->name;
  my $ga=$self->db->get_AuthorGroupAdaptor;
  if (!defined $group_id){
	 $group_id=$ga->fetch_id_by_name($group_name);
  }
  if (!defined $group_id){
	 warning("about to store new author-group $group_name");
	 $ga->store($group);
	 $group_id=$group->dbID;
  }
  # Insert new author entry
  my $sth = $self->prepare(q{
        INSERT INTO author(author_email,author_name, group_id) VALUES (?,?,?)
        });
  $sth->execute($author_email, $author_name,$group_id);
  my $db_id = $sth->{'mysql_insertid'} || throw('Failed to get autoincremented ID from statement handle');
  $author->dbID($db_id);

}

sub store_gene_author {
  my ($self,$gene_id,$author_id) = @_;
  unless ($gene_id || $author_id) {
	 throw("gene_id:$gene_id and author_id:$author_id must be present to store a gene_author");
  }
  # Insert new gene author
  my $sth = $self->prepare(q{
        INSERT INTO gene_author(gene_id, author_id) VALUES (?,?)
        });
  $sth->execute($gene_id,$author_id);
}

sub store_transcript_author {
  my ($self,$transcript_id,$author_id) = @_;
  unless ($transcript_id || $author_id) {
	 throw("transcript_id:$transcript_id and author_id:$author_id must be present to store a transcript_author");
  }
  # Insert new gene author
  my $sth = $self->prepare(q{
        INSERT INTO transcript_author(transcript_id, author_id) VALUES (?,?)
        });
  $sth->execute($transcript_id,$author_id);
}

1;

	





