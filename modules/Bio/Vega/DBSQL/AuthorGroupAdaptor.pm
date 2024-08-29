=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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

### Bio::Vega::DBSQL::AuthorGroupAdaptor.pm

package Bio::Vega::DBSQL::AuthorGroupAdaptor;

use strict;
use warnings;
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

    return;
}

sub store {
   my ($self, $group) = @_;

   return 1 if $self->exists_in_db($group);

   my $sth = $self->prepare(q{
        INSERT INTO author_group(group_name, group_email) VALUES (?,?)
        });
   $sth->execute($group->name, $group->email);
   my $id = $self->last_insert_id('group_id', undef, 'author_group')
       or $self->throw('Failed to get autoincremented ID from statement handle');
   $group->dbID($id);

   return $id;
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

Ana Code B<email> anacode@sanger.ac.uk

