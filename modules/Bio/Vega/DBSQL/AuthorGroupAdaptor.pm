### Bio::Vega::DBSQL::AuthorGroupAdaptor.pm

package Bio::Vega::DBSQL::AuthorGroupAdaptor;

use strict;
use Bio::Vega::AuthorGroup;
use Bio::EnsEMBL::Utils::Exception qw ( throw warning );
use base 'Bio::EnsEMBL::DBSQL::BaseAdaptor';


sub fetch_by_name {
    my ($self, $name) = @_;

    my $sth = $self->prepare(q{
          SELECT group_id
            , group_email
          FROM author_group
          WHERE group_name = ?
          });
    $sth->execute($name);
    my ($dbID, $email) = $sth->fetchrow;
    $sth->finish;

    if ($dbID) {
        my $group = Bio::Vega::AuthorGroup->new;
        $group->dbID($dbID);
        $group->name($name);
        $group->email($email);
    }
}

sub store {
   my ($self, $group) = @_;
   
   return 1 if $self->exists_in_db($group);
   
   my $sth = $self->prepare(q{
        INSERT INTO author_group(group_name, group_email) VALUES (?,?)
        });
	$sth->execute($group->name, $group->email);
	my $id = $sth->{'mysql_insertid'} or $self->throw('Failed to get autoincremented ID from statement handle');
	$group->dbID($id);
}

sub exists_in_db {
    my ($self, $group) = @_;
    
    if (my $db_group = $self->fetch_by_name($group->name)) {
        $group->dbID($db_group->dbID);
        $group->email($db_group->email);
        return 1;
    } else {
        return 0;
    }
}

1;

__END__

=head1 NAME - Bio::Vega::DBSQL::AuthorGroupAdaptor.pm

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk






