### Bio::Vega::DBSQL::AuthorGroupAdaptor.pm

package Bio::Vega::DBSQL::AuthorGroupAdaptor;

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

sub fetch_id_by_name{
  my ($self,$value) = @_;
  my $sth = $self->prepare(q{
        SELECT group_id
        FROM author_group
        WHERE name = ?
        });
  $sth->execute($value);
  my $dbID=$sth->fetchrow;
  $sth->finish;
  return $dbID;

}

sub store{
   my ($self,$value) = @_;
   my $sth = $self->prepare(q{
        INSERT INTO author_group(name) VALUES (?)
        });
	$sth->execute($value->name);
	my $id = $sth->{'mysql_insertid'} or $self->throw('Failed to get autoincremented ID from statement handle');
	$value->dbID($id);

}

1;

__END__

=head1 NAME - Bio::Vega::DBSQL::AuthorGroupAdaptor.pm

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk






