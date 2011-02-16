
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
}

sub new {
    my ($pkg, $home) = @_;
    
    unless ($home) {
        confess "Cannot create SQLite database without home parameter";
    }
    my $ref = "";
    my $self = bless \$ref, $pkg;
    my $file = "$home/otter.sqlite";
    $self->file($file);
    $self->init_db;
    
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

sub init_db {
    my ($self) = @_;
    
    my $file = $self->file or confess "Cannot create SQLite database: file not set";
    my $dbh = DBI->connect("dbi:SQLite:dbname=$file", undef, undef, {
        RaiseError => 1,
        AutoCommit => 1,
        });
    $dbh{$self} = $dbh;
    
    $self->create_tables;
    
    return 1;
}

{
    my %table_defs = (
        otter_filter  => q{
            filter_name TEXT        PRIMARY KEY
            , wanted    INTEGER DEFAULT 0
            , failed    INTEGER DEFAULT 0
            , done      INTEGER DEFAULT 0
            , gff_file  TEXT
        },
        accession_info  => q{
            accession_sv    TEXT    PRIMARY KEY
            , taxon_id      INTEGER
            , evi_type      TEXT
            , description   TEXT
            , source_db     TEXT
        },
    );

    sub create_tables {
        my ($self) = @_;

        my $dbh = $dbh{$self};

        my %existing_table = map {$_->[0], 1}
            @{ $dbh->selectall_arrayref(q{SELECT name FROM sqlite_master WHERE type = 'table'}) };

        foreach my $tab (sort keys %table_defs) {
            unless ($existing_table{$tab}) {
                $dbh->do("CREATE TABLE $tab ($table_defs{$tab})");
            }
        }
    }
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::DB

=head1 DESCRIPTION

The SQLite db stored in the local AceDatabase directory.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

