# Get a real Bio::Otter::Lace::DB, with database in a temporary directory,
# using a mock client if client not supplied.

package OtterTest::DB;

use strict;
use warnings;

use File::Basename;
use File::Temp;
use FindBin qw($Script);
use Test::More;

use OtterTest::Client;

use parent 'Bio::Otter::Lace::DB';

my %home;

sub new {
    my ($pkg, $client) = @_;

    $client ||= OtterTest::Client->new;

    my $_tmp_dir = File::Temp->newdir("${Script}.XXXXXX", TMPDIR => 1, CLEANUP => 0);
    my $home = $_tmp_dir->dirname;
    note "SQLite DB is in: '$home'";

    my $db = $pkg->SUPER::new($home, $client);

    $db->home($home);
    return $db;
}

sub home {
    my ($self, $arg) = @_;

    if ($arg) {
        $home{$self} = $arg;
    }
    return $home{$self};
}

sub DESTROY {
    my $self = shift;

    my $file = $self->file;
    my $home = $self->home;

    note "Removing '$file'";
    unlink $file;
    rmdir $home;

    delete($home{$self});

    return;
}

1;
