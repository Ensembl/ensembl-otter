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
    my $db = OtterTest::DB->new(client => $client);

    my $at_cache = $pkg->SUPER::new;
    $at_cache->Client($client);
    $at_cache->DB($db);

    return $at_cache;
}

1;
