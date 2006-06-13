### Bio::Vega::DBSQL::AuthorAdaptor.pm

package Bio::Vega::DBSQL::AuthorAdaptor;

use strict;
use Bio::Vega::Author;
use Bio::EnsEMBL::Utils::Exception qw ( throw warning );

use base 'Bio::EnsEMBL::DBSQL::BaseAdaptor';

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
  if ($self->fetch_by_name_email($author)){
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

sub fetch_by_name_email {
  my ($self,$author) = @_;
  if (!defined($author)) {
	 $self->throw("Name must be entered to fetch an author object");
  }
  my $author_name=$author->name;
  my $author_email=$author->email;
  my $sql = q{
		SELECT a.author_id,
             g.group_id,
             g.name
		FROM author a,author_group g
      WHERE a.author_name = ? AND a.author_email = ? AND a.group_id=g.group_id};
  my $sth = $self->prepare($sql);
  $sth->execute($author_name,$author_email);
  if (my $ref = $sth->fetchrow_hashref) {
	 $author->dbID($ref->{author_id});
	 my $group=new Bio::Vega::AuthorGroup;
	 $group->dbID($ref->{group_id});
	 $group->name($ref->{name});
	 $author->group($group);
	 return $author;
  } else {
	 return;
  }
}

1;

__END__

=head1 NAME - Bio::Vega::DBSQL::AuthorAdaptor.pm

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk






