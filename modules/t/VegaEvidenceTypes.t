#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Try::Tiny;
use Test::More;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;

my $module;
BEGIN {
    $module = 'Bio::Vega::Evidence::Types';
    use_ok($module, qw(new_evidence_type_valid evidence_type_valid_all evidence_is_sra_sample_accession));
}

use Bio::Vega::Evidence;

critic_module_ok($module);

my $evi_types = Bio::Vega::Evidence::Types->new;
isa_ok($evi_types, $module);

# OO

ok($evi_types->valid_for_new_evi('ncRNA'), 'ncRNA valid_for_new_evi (OO)');
ok($evi_types->valid_all('ncRNA'),         'ncRNA valid_all (OO)');

ok(not($evi_types->valid_for_new_evi('Genomic')), 'Genomic is NOT valid_for_new_evi (OO)');
ok($evi_types->valid_all('Genomic'),              'Genomic valid_all (OO)');

ok(not($evi_types->valid_for_new_evi('Garbage')), 'Garbage is NOT valid_for_new_evi (OO)');
ok(not($evi_types->valid_all('Garbage')),         'Garbage is NOT valid_all (OO)');

ok($evi_types->is_sra_sample_accession('DRS000234'), 'SRA sample accession (OO)');
ok(not($evi_types->is_sra_sample_accession('DRA000234')), 'SRA submission accession NOT a sample (OO)');

# Function

ok(new_evidence_type_valid('ncRNA'), 'ncRNA valid_for_new_evi (func)');
ok(evidence_type_valid_all('ncRNA'), 'ncRNA valid_all (func)');

ok(not(new_evidence_type_valid('Genomic')), 'Genomic is NOT valid_for_new_evi (func)');
ok(evidence_type_valid_all('Genomic'),      'Genomic valid_all (func)');

ok(not(new_evidence_type_valid('Garbage')), 'Garbage is NOT valid_for_new_evi (func)');
ok(not(evidence_type_valid_all('Garbage')), 'Garbage is NOT valid_all (func)');

ok(evidence_is_sra_sample_accession('SRS000012'), 'SRA sample accession (func)');
ok(not(evidence_is_sra_sample_accession('AC123456.7')), 'Not an SRA sample accession (func)');

# Check it works in a client module

my $dba = bless {}, 'Bio::EnsEMBL::DBSQL::BaseAdaptor';
my $evi = Bio::Vega::Evidence->new(-adaptor => $dba, -name => 'test');
isa_ok($evi, 'Bio::Vega::Evidence');
ok($evi->type('cDNA'), 'type to cDNA');
is($evi->type,'cDNA',  'type is cDNA');
ok($evi->type('Genomic'), 'type to Genomic');
is($evi->type,'Genomic',  'type is Genomic');

my ($okay, $error);
try {
    $evi->type('Garbage');
    $okay = 1;
} catch {
    $error = $_;
};
ok(not($okay), 'cannot mis-set type');
like($error, qr/Must be one of Protein,ncRNA,cDNA,EST,SRA,Genomic/, 'error message ok');
is($evi->type,'Genomic',  'type is still Genomic');

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
