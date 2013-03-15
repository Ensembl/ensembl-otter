
### Bio::Otter::Lace::DB

package Bio::Otter::Lace::DB;

use strict;
use warnings;
use Carp;
use DBI;

my(
    %dbh,
    %file,
    );

sub DESTROY {
    my ($self) = @_;

    delete($dbh{$self});
    delete($file{$self});

    return;
}

sub new {
    my ($pkg, $home, $client) = @_;

    unless ($home) {
        confess "Cannot create SQLite database without home parameter";
    }
    my $ref = "";
    my $self = bless \$ref, $pkg;
    my $file = "$home/otter.sqlite";
    $self->file($file);
    $self->init_db($client);

    return $self;
}

sub dbh {
    my ($self, $arg) = @_;

    if ($arg) {
        $dbh{$self} = $arg;
    }
    return $dbh{$self};
}

sub file {
    my ($self, $arg) = @_;

    if ($arg) {
        $file{$self} = $arg;
    }
    return $file{$self};
}

sub get_tag_value {
    my ($self, $tag) = @_;

    my $sth = $dbh{$self}->prepare(q{ SELECT value FROM tag_value WHERE tag = ? });
    $sth->execute($tag);
    my ($value) = $sth->fetchrow;
    return $value;
}

sub set_tag_value {
    my ($self, $tag, $value) = @_;

    unless (defined $value) {
        confess "No value provided";
    }

    my $sth = $dbh{$self}->prepare(q{ INSERT OR REPLACE INTO tag_value (tag, value) VALUES (?,?) });
    $sth->execute($tag, $value);

    return;
}

sub _has_table {
    my ($self, $table) = @_;
    my $sth = $dbh{$self}->table_info(undef, 'main', $table, 'TABLE');
    my $table_info = $sth->fetchrow_hashref;
    return unless $table_info;
    return $table_info->{TABLE_NAME};
}

sub init_db {
    my ($self, $client) = @_;

    my $file = $self->file or confess "Cannot create SQLite database: file not set";
    my $dbh = DBI->connect("dbi:SQLite:dbname=$file", undef, undef, {
        RaiseError => 1,
        AutoCommit => 1,
        sqlite_allow_multiple_statements => 1,
        });
    $dbh{$self} = $dbh;

    $self->create_tables($client) unless $self->_has_table('tag_value') and $self->get_tag_value('initialised');

    return 1;
}

sub create_tables {
    my ($self, $client) = @_;

    my $schema = $client->get_otter_schema;

    my $dbh = $dbh{$self};
    $dbh->begin_work;
    $dbh->do($schema);
    $self->set_tag_value('initialised', 1);
    $dbh->commit;

    return;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::DB

=head1 DESCRIPTION

The SQLite db stored in the local AceDatabase directory.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

