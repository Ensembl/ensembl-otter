#!/usr/bin/env perl

use strict;
use warnings;

use Test::More;
use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

my $vud_module;
BEGIN {
    $vud_module = 'Bio::Vega::Utils::Detaint';
    use_ok($vud_module, qw( detaint_url_fmt detaint_pfam_url_fmt ));
}
critic_module_ok($vud_module);

my $plain = 'http://www.ensembl.org/Rattus_norvegicus/Location/View?gene=%s';
my $pfam  = 'http://pfam.sanger.ac.uk/family?entry=%{pfam}';

my $plain_bad = "http://www.ensembl.org/Rattus_norvegicus/Location/View?gene=%s\nDELETE";
my $pfam_bad  = 'http://pfam.sanger.ac.uk/family?entry=%{pfam}/ cruft';

is(detaint_url_fmt($plain),      $plain, 'detaint_url_fmt($plain)');
is(detaint_pfam_url_fmt($plain), $plain, 'detaint_pfam_url_fmt($plain)');

is(detaint_url_fmt($pfam),      undef, 'detaint_url_fmt($pfam)');
is(detaint_pfam_url_fmt($pfam), $pfam, 'detaint_pfam_url_fmt($pfam)');

is(detaint_url_fmt($plain_bad),      undef, 'detaint_url_fmt($plain_bad)');
is(detaint_pfam_url_fmt($plain_bad), undef, 'detaint_pfam_url_fmt($plain_bad)');

is(detaint_url_fmt($pfam_bad),      undef, 'detaint_url_fmt($pfam_bad)');
is(detaint_pfam_url_fmt($pfam_bad), undef, 'detaint_pfam_url_fmt($pfam_bad)');

done_testing;

# Local Variables:
# mode: perl
# End:

# EOF
