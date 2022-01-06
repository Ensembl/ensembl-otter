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


### Bio::Otter::Lace::DB::Adaptor

package Bio::Otter::Lace::DB::Adaptor;

use strict;
use warnings;
use Carp qw( carp confess );

sub new {
    my ($pkg, $dbh) = @_;

    confess "dbh must be supplied" unless $dbh;

    my $self = bless {}, $pkg;
    $self->dbh($dbh);

    return $self;
}

sub dbh {
    my ($self, $dbh) = @_;

    if ($dbh) {
        $self->{'_dbh'} = $dbh;
    }
    return $self->{'_dbh'};
}

## These methods must be overridden in the child adaptor:

sub columns {
    confess "columns() must be defined by subclass";
}

sub key_column_name {
    confess "key_column_name() must be defined by subclass";
}

sub SQL {
    confess "SQL() must be defined by subclass";
}

## These methods can be overridden in the child adaptor:

sub key_is_auto_increment {
    return;
}

#

sub object_class {
    return;
}

# or, if not, then override...

sub new_object {
    my ($self, %attribs) = @_;
    my $obj_class = $self->object_class;
    confess "object_class() must be provided by subclass to use new_object()" unless $obj_class;
    return $obj_class->new(%attribs);
}

## ^^^ End of standard overrideable methods ^^^

sub all_columns {
    my ($self) = @_;
    return join(', ', $self->columns);
}

sub check_object {
    my ($self, $object) = @_;

    confess "Object must be supplied" unless $object;

    if (my $obj_class = $self->object_class) {
        confess "'$object' is not a $obj_class" unless $object->isa($obj_class);
    }

    return $object;
}

sub store {
    my ($self, $object) = @_;
    $self->check_object($object);
    confess "Object already stored" if $object->is_stored;
    return $self->_store($object);
}

sub _store {
    my ($self, $object) = @_;

    my $result = $self->_store_sth->execute(map { $object->$_() } $self->columns);
    $object->is_stored(1) if $result;

    if ($self->key_is_auto_increment) {
        my $key_column_name = $self->key_column_name;
        unless (defined $object->$key_column_name) {
            $object->$key_column_name($self->dbh->last_insert_id("", "", "", ""));
        }
    }

    return $result;
}

sub update {
    my ($self, $object) = @_;
    $self->check_object($object);
    confess "Object not stored" unless $object->is_stored;
    return $self->_update($object);
}

sub _update {
    my ($self, $object) = @_;
    my $key_column_name = $self->key_column_name;
    my $result = $self->_update_sth->execute((map { $object->$_() } $self->columns), $object->$key_column_name());
    return $result;
}

sub store_or_update {
    my ($self, $object) = @_;
    $self->check_object($object);
    if ($object->is_stored) {
        return $self->_update($object);
    } else {
        return $self->_store($object);
    }
}

sub delete {
    my ($self, $object) = @_;
    $self->check_object($object);
    confess "Object not stored" unless $object->is_stored;

    my $key_column_name = $self->key_column_name;
    my $result = $self->_delete_sth->execute($object->$key_column_name);
    $object->is_stored(0) if $result;

    return $result;
}

sub _fetch_by_key {
    my ($self, $key) = @_;

    my $sth = $self->_fetch_by_key_sth;
    $sth->execute($key);
    my $attribs = $sth->fetchrow_hashref;
    return $attribs;
}

sub fetch_by_key {
    my ($self, $key) = @_;

    my $attribs = $self->_fetch_by_key($key);
    return unless $attribs;

    my $object = $self->new_object(%$attribs);
    $object->is_stored(1);
    return $object;
}

sub fetch_state {
    my ($self, $object) = @_;
    $self->check_object($object);

    my $key_column_name = $self->key_column_name;
    my $attribs = $self->_fetch_by_key($object->$key_column_name);
    return unless $attribs;

    while (my ($key, $value) = each %$attribs) {
        $object->$key($value);
    }
    $object->is_stored(1);

    return $object;
}

sub fetch_by {
    my ($self, $sth, $multi_warn_fmt, @args) = @_;

    $sth->execute(@args);
    my $attribs = $sth->fetchrow_hashref;
    return unless $attribs;

    my $object = $self->new_object(%$attribs);
    $object->is_stored(1);

    if ($multi_warn_fmt and $sth->fetchrow_hashref) {
        carp sprintf($multi_warn_fmt, @args);
    }

    return $object;
}

sub _store_sth         { return shift->_prepare_canned('store'); }
sub _update_sth        { return shift->_prepare_canned('update'); }
sub _delete_sth        { return shift->_prepare_canned('delete'); }
sub _fetch_by_key_sth  { return shift->_prepare_canned('fetch_by_key'); }

sub _prepare_canned {
    my ($self, $name) = @_;
    return $self->_prepare_cached("_${name}_sth", $self->SQL->{$name});
}

sub _prepare_cached {
    my ($self, $name, $sql) = @_;
    return $self->{$name} if $self->{$name};

    return $self->{$name} = $self->dbh->prepare($sql);
}

sub begin_work { return shift->dbh->do('BEGIN IMMEDIATE TRANSACTION'); }
sub commit     { return shift->dbh->commit;     }
sub rollback   { return shift->dbh->rollback;   }

1;

__END__

=head1 NAME - Bio::Otter::Lace::DB::Adaptor

=head1 AUTHOR

Michael Gray B<email> mg13@sanger.ac.uk

