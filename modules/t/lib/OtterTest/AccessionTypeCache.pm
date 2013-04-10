# Get a real Bio::Otter::Lace::AccessionTypeCache, 
# with connected DB and mock client.

package OtterTest::AccessionTypeCache;

use strict;
use warnings;

use OtterTest::Client;
use OtterTest::DB;

use parent 'Bio::Otter::Lace::AccessionTypeCache';

sub new {
    my ($pkg) = @_;

    my $client = OtterTest::Client->new;
    my $db = OtterTest::DB->new($client);

    my $at_cache = $pkg->SUPER::new;
    $at_cache->Client($client);
    $at_cache->DB($db);

    return $at_cache;
}

1;
