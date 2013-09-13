
### Bio::Otter::Lace::DB::ColumnAdaptor

package Bio::Otter::Lace::DB::ColumnAdaptor;

use strict;
use warnings;
use Carp;

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

my @columns = qw( selected status status_detail gff_file process_gff name );

my $all_columns = join(', ', @columns);

my %SQL = (
    store =>            qq{ INSERT INTO otter_column ( ${all_columns} )
                                              VALUES ( ?, ?, ?, ?, ?, ? )
                          },
    update =>            q{ UPDATE otter_column
                               SET selected = ?, status = ?, status_detail = ? , gff_file = ?, process_gff = ?
                             WHERE name = ?
                          },
    delete =>            q{ DELETE FROM otter_column WHERE name = ?
                          },
    fetch_by_name =>    qq{ SELECT ${all_columns} FROM otter_column WHERE name = ?
                          },
    update_for_filter_get => qq{ UPDATE otter_column
                                    SET status = 'Loading', gff_file = ?, process_gff = ?
                                  WHERE name = ?
                               },
);

sub store {
    my ($self, $column) = @_;
    $self->_check_column($column);
    confess "Column already stored" if $column->is_stored;

    my $result = $self->_store_sth->execute(map { $column->$_() } @columns);
    $column->is_stored(1) if $result;

    return $result;
}

sub update {
    my ($self, $column) = @_;
    $self->_check_column($column);
    confess "Column not stored" unless $column->is_stored;

    my $result = $self->_update_sth->execute(map { $column->$_() } @columns);
    return $result;
}

sub delete {
    my ($self, $column) = @_;
    $self->_check_column($column);
    confess "Column not stored" unless $column->is_stored;

    my $result = $self->_delete_sth->execute($column->name);
    $column->is_stored(0) if $result;

    return $result;
}

sub fetch_state {
    my ($self, $column) = @_;
    $self->_check_column($column);

    my $sth = $self->_fetch_by_name_sth;
    $sth->execute($column->name);
    my $attribs = $self->_fetch_by_name_sth->fetchrow_hashref;
    return unless $attribs;
    while (my ($key, $value) = each %$attribs) {
        $column->$key($value);
    }
    $column->is_stored(1);
}

sub _check_column {
    my ($self, $column) = @_;

    confess "Column must be supplied" unless $column;
    confess "'$column' is not a Bio::Otter::Lace::Source::Item::Column"
      unless $column->isa('Bio::Otter::Lace::Source::Item::Column');

    return $column;
}


# Special atomic update for filter_get script.
#
sub update_for_filter_get {
    my ($self, $name, $gff_file, $process_gff) = @_;
    my $sth = $self->dbh->prepare($SQL{update_for_filter_get});
    return $sth->execute($gff_file, $process_gff, $name);
}

sub _store_sth         { return shift->_prepare_canned('store'); }
sub _update_sth        { return shift->_prepare_canned('update'); }
sub _delete_sth        { return shift->_prepare_canned('delete'); }
sub _fetch_by_name_sth { return shift->_prepare_canned('fetch_by_name'); }

sub _prepare_canned {
    my ($self, $name) = @_;
    return $self->_prepare_cached("_${name}_sth", $SQL{$name});
}

sub _prepare_cached {
    my ($self, $name, $sql) = @_;
    return $self->{$name} if $self->{$name};

    return $self->{$name} = $self->dbh->prepare($sql);
}

sub begin_work { return shift->dbh->do('BEGIN IMMEDIATE TRANSACTION'); }
sub commit     { return shift->dbh->commit;     }
sub rollback   { return shift->dbh->rollback;   }

sub fetch_ColumnCollection_state {
    my ($self, $clltn) = @_;

    foreach my $col ($clltn->list_Columns) {
        $self->fetch_state($col);
    }
}

sub store_ColumnCollection_state {
    my ($self, $clltn) = @_;

    $self->begin_work;
    foreach my $col ($clltn->list_Columns) {
        if ($col->is_stored) {
            $self->update($col);
        }
        else {
            $self->store($col);
        }
    }
    $self->commit;
}

sub store_Column_state {
    my ($self, $col) = @_;

    $self->begin_work;
    if ($col->is_stored) {
        $self->update($col);
    }
    else {
        $self->store($col);
    }
    $self->commit;
}


1;

__END__

=head1 NAME - Bio::Otter::Lace::DB::ColumnAdaptor

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

