# Get a real Bio::Otter::Lace::DB, with database in a temporary directory,
# using a mock client if client not supplied.

package OtterTest::DB;

use strict;
use warnings;

use File::Basename;
use File::Temp;
use FindBin qw($Script);
use Test::More;

use Bio::Otter::Lace::DataSet;

use OtterTest::Client;

use parent 'Bio::Otter::Lace::DB';

my (
    %test_home,
    %test_client,
    );

sub new {
    my ($pkg, $client) = @_;

    $client ||= OtterTest::Client->new;

    my $_tmp_dir = File::Temp->newdir("${Script}.XXXXXX", TMPDIR => 1, CLEANUP => 0);
    my $test_home = $_tmp_dir->dirname;
    note "SQLite DB is in: '$test_home'";

    my $db = $pkg->SUPER::new($test_home, $client);

    $db->test_client($client);
    $db->test_home($test_home);

    return $db;
}

sub new_with_dataset_info {
    my ($pkg, $client, $dataset_name) = @_;

    my $db = $pkg->new($client);

    my $test_dataset = Bio::Otter::Lace::DataSet->new;
    $test_dataset->Client($db->test_client);
    $db->load_dataset_info($test_dataset);

    return $db;
}

sub test_client {
    my ($self, $arg) = @_;

    if ($arg) {
        $test_client{$self} = $arg;
    }
    return $test_client{$self};
}

sub test_home {
    my ($self, $arg) = @_;

    if ($arg) {
        $test_home{$self} = $arg;
    }
    return $test_home{$self};
}

sub setup_chromosome_slice {
    my ($self) = @_;
    my $dbh = $self->dbh;

    $dbh->begin_work;
    $dbh->do(<< '_EO_SQL_');
    INSERT INTO seq_region (seq_region_id, name, coord_system_id, length)
                   SELECT 10111, 'test_chr', coord_system_id, 4000000
                     FROM coord_system cs WHERE cs.name = 'chromosome'
_EO_SQL_
    $dbh->commit;
    return;
}

sub DESTROY {
    my $self = shift;

    my $file = $self->file;
    my $test_home = $self->test_home;

    note "Removing '$file'";
    unlink $file;
    rmdir $test_home;

    delete($test_home{$self});
    delete($test_client{$self});

    return;
}

1;
