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


### Bio::Otter::Lace::DB::ColumnAdaptor

package Bio::Otter::Lace::DB::ColumnAdaptor;

use strict;
use warnings;
use Carp;

use Bio::Otter::Lace::Chooser::Item::Column;

use base 'Bio::Otter::Lace::DB::Adaptor';

sub columns         { return qw( selected status status_detail gff_file process_gff name ); }
sub key_column_name { return 'name'; }
sub object_class    { return 'Bio::Otter::Lace::Chooser::Item::Column'; }

my $all_columns = __PACKAGE__->all_columns;

sub new_object {
    my ($self, %attribs) = @_;
    my $obj = $self->SUPER::new_object;
    foreach my $method ( $self->columns ) {
        $obj->$method($attribs{$method});
    }
    return $obj;
}

sub SQL {
    return {
    store =>            qq{ INSERT INTO otter_column ( ${all_columns} )
                                              VALUES ( ?, ?, ?, ?, ?, ? )
                          },
    update =>            q{ UPDATE otter_column
                               SET selected = ?
                                 , status = ?
                                 , status_detail = ?
                                 , gff_file = ?
                                 , process_gff = ?
                                 , name = ?
                             WHERE name = ?
                          },
    delete =>            q{ DELETE FROM otter_column WHERE name = ?
                          },
    fetch_by_key  =>    qq{ SELECT ${all_columns} FROM otter_column WHERE name = ?
                          },
    update_for_filter_script => qq{ UPDATE otter_column
                                      SET status = 'Loading', gff_file = ?, process_gff = ?
                                    WHERE name = ?
                               },
    };
}

# Special atomic update for filter_get script.
#
sub update_for_filter_script {
    my ($self, $name, $gff_file, $process_gff) = @_;
    my $sth = $self->dbh->prepare($self->SQL->{update_for_filter_script});
    return $sth->execute($gff_file, $process_gff, $name);
}

sub fetch_ColumnCollection_state {
    my ($self, $clltn) = @_;

    my $fetched;
    foreach my $col ($clltn->list_Columns) {
        $self->fetch_state($col) and ++$fetched;
    }

    return $fetched;
}

sub store_ColumnCollection_state {
    my ($self, $clltn) = @_;

    my $saved;
    $self->begin_work;
    foreach my $col ($clltn->list_Columns) {
        if ($col->is_stored) {
            $self->update($col) and ++$saved;
        }
        else {
            $self->store($col)  and ++$saved;
        }
    }
    $self->commit;

    return $saved;
}

sub store_Column_state {
    my ($self, $col) = @_;

    $self->begin_work;
    my $result;
    if ($col->is_stored) {
        $result = $self->update($col);
    }
    else {
        $result = $self->store($col);
    }
    $self->commit;

    return $result;
}


1;

__END__

=head1 NAME - Bio::Otter::Lace::DB::ColumnAdaptor

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

