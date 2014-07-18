#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Test::More;
use Test::Otter qw( ^db_or_skipall );

use Bio::Otter::Server::Support::Local;

my ($sa_ai_module, $sa_ai_tsv_module);

BEGIN {
    $sa_ai_module = qw( Bio::Otter::ServerAction::AccessionInfo );
    $sa_ai_tsv_module = qw( Bio::Otter::ServerAction::TSV::AccessionInfo );
    use_ok($sa_ai_module);
    use_ok($sa_ai_tsv_module);
}

critic_module_ok($sa_ai_module);
critic_module_ok($sa_ai_tsv_module);

my $server = Bio::Otter::Server::Support::Local->new;

my $ai_plain = new_ok($sa_ai_module => [ $server ]);
my $ai_tsv = new_ok($sa_ai_tsv_module => [ $server ]);

my @accessions = qw( AK125401.1 Q14031.3 ERS000123 xyzzy );
$server->set_params( accessions => \@accessions );
my $results = $ai_plain->get_accession_types;
ok($results, 'get_accession_types');
is(scalar keys %$results, 3, 'n(results)');

# TSV is now a misnomer as it's used only to deserialise the list of incoming accessions.
$server->set_params( accessions => join(',', @accessions) );
$results = $ai_tsv->get_accession_types;
ok($results, 'get_accession_types - TSV');
is(scalar keys %$results, 3, 'n(results)');

my @taxon_ids = ( 9606, 10090, 90988, 12345678 );
$server->set_params( id => \@taxon_ids );
$results = $ai_plain->get_taxonomy_info;
ok($results, 'get_taxonomy_info');
SKIP: {
# FIXME: serialisation in the wrong place to match deserialisation, so...
skip 'serialisation in wrong place for now', 1;
is(scalar @$results, 3, 'n(results)');
}

$server->set_params( id => join(',', @taxon_ids) );
$results = $ai_tsv->get_taxonomy_info;
ok($results, 'get_taxonomy_info - TSV');
note("Got:\n", $results);

done_testing;

# Local Variables:
# mode: perl
# End:

# EOF
