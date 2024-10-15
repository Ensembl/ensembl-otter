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

# Get a real Bio::Otter::Lace::DB, with database in a temporary directory,
# using a mock client if client not supplied.

package OtterTest::DB;

use strict;
use warnings;

use File::Basename;
use File::Temp;
use FindBin qw($Script);
use Test::More;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::SetupLog4perl;

use Bio::Otter::Lace::DataSet;

use OtterTest::Client;

use parent 'Bio::Otter::Lace::DB';

my %test_client;

sub new {
    my ($pkg, %args) = @_;

    $args{client} ||= OtterTest::Client->new;

    my $_tmp_dir = File::Temp->newdir("${Script}.XXXXXX", TMPDIR => 1, CLEANUP => 0);
    my $test_home = $_tmp_dir->dirname;
    note "SQLite DB is in: '$test_home'";

    my $db = $pkg->SUPER::new(home => $test_home, %args);

    $db->test_client($args{client});

    return $db;
}

sub new_with_dataset_info {
    my ($pkg, %args) = @_;

    my $db = $pkg->new(%args, species => $args{dataset_name});

    my $test_dataset = Bio::Otter::Lace::DataSet->new;
    $test_dataset->name($args{dataset_name});
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
    my $test_home = dirname $file;

    note "Removing '$file'";
    unlink $file;
    rmdir $test_home;

    delete($test_client{$self});

    return;
}

1;
