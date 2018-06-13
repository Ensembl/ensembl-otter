=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Bio::Vega::DBSQL::AuthorAdaptor;

use strict;
use warnings;
use Bio::Vega::Author;
use Bio::Vega::AuthorGroup;
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
    my ($self, $where_clause, @args) = @_;

    my $sql = qq{
        SELECT a.author_id as author_id
          , a.author_email as author_email
          , a.author_name as author_name
          , g.group_id as group_id
          , g.group_name as group_name
          , g.group_email as group_email
        FROM author a
        LEFT JOIN author_group g
          ON a.group_id = g.group_id
        WHERE $where_clause
        };

    my $sth = $self->prepare($sql);
    $sth->execute(@args);

    if (my $ref = $sth->fetchrow_hashref) {

        # Make a new author object
        my $author = Bio::Vega::Author->new;
        $author->dbID($ref->{author_id});
        $author->email($ref->{author_email});
        $author->name($ref->{author_name});
        $author->adaptor($self);

        # Give it a group if it has one
        if (my $gid = $ref->{group_id}) {
            my $group = Bio::Vega::AuthorGroup->new;
            $group->dbID($gid);
            $group->name($ref->{group_name});
            $group->email($ref->{group_email});
            $author->group($group);
        }

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
    my ($self, $id) = @_;

    if (!defined($id)) {
        $self->throw("Id must be entered to fetch an author object");
    }

    return $self->_generic_sql_fetch("author_id = ?", $id);
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
    my ($self, $name) = @_;

    unless ($name) {
        $self->throw("Name must be entered to fetch an author object");
    }

    return $self->_generic_sql_fetch("author_name = ?", $name);
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
    my ($self, $email) = @_;

    unless ($email) {
        $self->throw("Email address must be entered to fetch an author object");
    }

    my $author = $self->_generic_sql_fetch("author_email = ?", $email);

    return $author;
}

sub exists_in_db {
  my ($self, $author) = @_;

  unless ($author->name) {
      throw("Name is empty in the author object - should be set to check for exsistence");
  }

  if (my $db_author = $self->fetch_by_name($author->name)) {
    foreach my $method (qw{ dbID name email group }) {
        $author->$method($db_author->$method());
    }
    return 1;
  } else {
    return 0;
  }
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
    my ($self, $author) = @_;
    if (!defined($author)) {
        throw("Must provide an author object to the store method");
    } elsif (! $author->isa("Bio::Vega::Author")) {
        throw("Argument must be an author object to the store method.  Currently is [$author]");
    }
    my $author_name  = $author->name  || throw "Author does not have a name";
    my $author_email = $author->email || throw "Author does not have an email address";

    # Is this author already in the database?
    if ($self->exists_in_db($author)) {
        return 1;
    }

    my $group_id;
    if (my $group = $author->group) {
        unless ($group->dbID) {
            $self->db->get_AuthorGroupAdaptor->store($group);
        }
        $group_id = $group->dbID;
    }

    # Insert new author entry
    my $sth;
    if ($group_id) {
        $sth = $self->prepare(q{
              INSERT INTO author(author_email, author_name, group_id) VALUES (?,?,?)
              });
        $sth->execute($author_email, $author_name, $group_id);
    } else {
        $sth = $self->prepare(q{
              INSERT INTO author(author_email, author_name) VALUES (?,?)
              });
        $sth->execute($author_email, $author_name);
    }

    my $db_id = $self->last_insert_id('author_id', undef, 'author')
        || throw('Failed to get autoincremented ID from statement handle');
    $author->dbID($db_id);
    $author->adaptor($self);

    return;
}

sub store_gene_author {
  my ($self, $gene_id, $author_id) = @_;
  unless ($gene_id || $author_id) {
      throw("gene_id:$gene_id and author_id:$author_id must be present to store a gene_author");
  }
  # Insert new gene author
  my $sth = $self->prepare(q{
        INSERT INTO gene_author(gene_id, author_id) VALUES (?,?)
        });
  $sth->execute($gene_id,$author_id);
  return;
}

sub remove_gene_author {
    my ($self, $gene_id, $author_id) = @_;

    my $sth = $self->prepare(q{
        DELETE FROM gene_author where gene_id = ? AND author_id = ?
        });
    $sth->execute($gene_id, $author_id);
    return;
}

sub store_transcript_author {
  my ($self, $transcript_id, $author_id) = @_;
  unless ($transcript_id || $author_id) {
      throw("transcript_id:$transcript_id and author_id:$author_id must be present to store a transcript_author");
  }
  # Insert new gene author
  my $sth = $self->prepare(q{
        INSERT INTO transcript_author(transcript_id, author_id) VALUES (?,?)
        });
  $sth->execute($transcript_id,$author_id);
  return;
}

sub remove_transcript_author {
    my ($self, $transcript_id, $author_id) = @_;

    my $sth = $self->prepare(q{
        DELETE FROM transcript_author where transcript_id = ? AND author_id = ?
        });
    $sth->execute($transcript_id, $author_id);
    return;
}

sub fetch_gene_author {
  my ($self, $gene_id) = @_;
  unless ($gene_id) {
      throw("gene_id:$gene_id  must be present to fetch a gene_author");
  }
  my $sth = $self->prepare(q{
        SELECT author_id from gene_author where gene_id=?
        });
  $sth->execute($gene_id);
  my ($author_id) = $sth->fetchrow_array();
  $sth->finish();
  return unless defined $author_id;
  my $author=$self->fetch_by_dbID($author_id);
  return $author;
}

sub fetch_transcript_author {
  my ($self, $transcript_id) = @_;
  unless ($transcript_id) {
      throw("transcript_id:$transcript_id  must be present to fetch a transcript_author");
  }
  my $sth = $self->prepare(q{
        SELECT author_id from transcript_author where transcript_id=?
        });
  $sth->execute($transcript_id);
  my ($author_id) = $sth->fetchrow_array();
  $sth->finish();
  return unless defined $author_id;
  my $author=$self->fetch_by_dbID($author_id);
  return $author;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

