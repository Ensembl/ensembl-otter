=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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


### Bio::Otter::Lace::DB::OTFRequestAdaptor

package Bio::Otter::Lace::DB::OTFRequestAdaptor;

use strict;
use warnings;

use Carp qw(cluck confess croak carp);

use Bio::Otter::Lace::DB::OTFRequest;

use base 'Bio::Otter::Lace::DB::Adaptor';

sub columns { return qw(
                  id
                  logic_name
                  target_start
                  command
                  fingerprint
                  status
                  n_hits
                  transcript_id
                  caller_ref
                  raw_result
                  ); }

sub key_column_name       { return 'id'; }
sub key_is_auto_increment { return 1;    }

sub object_class { return 'Bio::Otter::Lace::DB::OTFRequest'; }

my $all_columns = __PACKAGE__->all_columns;

sub SQL {
    return {
    store =>            qq{ INSERT INTO otter_otf_request ( ${all_columns} )
                                                   VALUES ( ?, ?, ?, ?, ?, ?, ?, ?, ?, ? )
                          },
    update =>            q{ UPDATE otter_otf_request
                               SET id           = ?
                                 , logic_name   = ?
                                 , target_start = ?
                                 , command      = ?
                                 , fingerprint  = ?
                                 , status       = ?
                                 , n_hits       = ?
                                 , transcript_id = ?
                                 , caller_ref    = ?
                                 , raw_result    = ?
                             WHERE id = ?
                          },
    update_status =>     q{ UPDATE otter_otf_request SET status = ? WHERE id = ? },
    delete =>            q{ DELETE FROM otter_otf_request WHERE id = ?
                          },
    fetch_by_key =>     qq{ SELECT ${all_columns} FROM otter_otf_request WHERE id = ?
                          },
    fetch_by_logic_name_status => qq{ SELECT ${all_columns} FROM otter_otf_request WHERE logic_name = ? AND status = ?
                             },
    already_running =>   q{ SELECT id FROM otter_otf_request WHERE fingerprint = ? AND STATUS IN ('new','running')
                          },
    store_arg =>         q{ INSERT INTO otter_otf_args ( request_id, key, value ) VALUES ( ?, ?, ? )
                          },
    fetch_args =>        q{ SELECT key, value FROM otter_otf_args WHERE request_id = ?
                          },
    store_missed_hit =>  q{ INSERT INTO otter_otf_missed_hits ( request_id, query_name ) VALUES ( ?, ? )
                          },
    fetch_missed_hits => q{ SELECT query_name FROM otter_otf_missed_hits WHERE request_id = ?
                          },
    delete_missed_hits =>q{ DELETE FROM otter_otf_missed_hits WHERE request_id = ?
                          },
    };
}

sub store {
    my ($self, $object) = @_;

    my $result = $self->SUPER::store($object);
    unless ($result == 1) {
        cluck "store returned '$result'";
        return;
    }

    while (my ($key, $value) = each %{$object->args}) {
        $self->_store_arg($object->id, $key, $value);
    }

    $self->_store_missed_hits($object) if $object->missed_hits;

    return $result;
}

sub _store_arg {
    my ($self, $id, $key, $value) = @_;
    return $self->_store_arg_sth->execute($id, $key, $value);
}

sub _store_arg_sth { return shift->_prepare_canned('store_arg') };

sub _store_missed_hits {
    my ($self, $object) = @_;

    my $count = 0;
    foreach my $query_name (@{$object->missed_hits}) {
        $self->_store_missed_hit($object->id, $query_name);
        $count++;
    }
    return $count;
}

sub _store_missed_hit {
    my ($self, $id, $query_name) = @_;
    return $self->_store_missed_hit_sth->execute($id, $query_name);
}

sub _store_missed_hit_sth { return shift->_prepare_canned('store_missed_hit') };

sub fetch_by_logic_name_status {
    my ($self, $logic_name, $status) = @_;

    my $sth = $self->_fetch_by_logic_name_status_sth;
    my $object = $self->fetch_by($sth, "multiple requests for {logic name:'%s', status:'%s'}", $logic_name, $status);
    return unless $object;

    $self->_fetch_args($object);
    $self->_fetch_missed_hits($object);

    return $object;
}

sub _fetch_by_logic_name_status_sth { return shift->_prepare_canned('fetch_by_logic_name_status'); }

sub already_running {
    my ($self, $object) = @_;

    my $sth = $self->_already_running_sth;
    $sth->execute($object->fingerprint);
    my $rowref = $sth->fetchall_arrayref;
    return unless @$rowref;
    return map { $_->[0] } @$rowref;
}

sub _already_running_sth { return shift->_prepare_canned('already_running'); }

sub _fetch_args {
    my ($self, $object) = @_;

    my $sth = $self->_fetch_args_sth;
    $sth->execute($object->id);
    my $args = {};
    while (my $row = $sth->fetchrow_arrayref) {
        my ($key, $value) = @$row;
        $args->{$key} = $value;
    }
    $object->args($args);
    return $object;
}

sub _fetch_args_sth { return shift->_prepare_canned('fetch_args') };

sub _fetch_missed_hits {
    my ($self, $object) = @_;

    my $sth = $self->_fetch_missed_hits_sth;
    $sth->execute($object->id);
    my $rows = $sth->fetchall_arrayref;
    my @query_names = map { $_->[0] } @$rows;
    $object->missed_hits(\@query_names) if @query_names;
    return $object;
}

sub _fetch_missed_hits_sth { return shift->_prepare_canned('fetch_missed_hits') };

sub update {
    my ($self, $object) = @_;

    my $result = $self->SUPER::update($object);
    unless ($result == 1) {
        cluck "store returned '$result'";
        return;
    }

    if ($object->missed_hits) {
        $self->_delete_missed_hits($object->id);
        $self->_store_missed_hits($object);
    }

    return $result;
}

sub update_status {
    my ($self, $object) = @_;
    return $self->_update_status_sth->execute($object->status, $object->id);
}

sub _update_status_sth { return shift->_prepare_canned('update_status') };

sub _delete_missed_hits {
    my ($self, $id) = @_;
    return $self->_delete_missed_hits_sth->execute($id);
}

sub _delete_missed_hits_sth { return shift->_prepare_canned('delete_missed_hits') };

1;

__END__

=head1 NAME - Bio::Otter::Lace::DB::OTFRequestAdaptor

=head1 AUTHOR

Michael Gray B<email> mg13@sanger.ac.uk

