#!/usr/bin/env perl

use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;
use Test::SetupLog4perl;

use Test::More;

# use_ok and critic_ok tests on OTF modules which do not have individual tests

my @modules;

BEGIN {

    @modules = qw(
        Bio::Otter::Lace::OnTheFly
        Bio::Otter::Lace::OnTheFly::Builder
        Bio::Otter::Lace::OnTheFly::Builder::Transcript
        Bio::Otter::Lace::OnTheFly::FastaFile
        Bio::Otter::Lace::OnTheFly::Format::Ace
        Bio::Otter::Lace::OnTheFly::Format::GFF
        Bio::Otter::Lace::OnTheFly::ResultSet
        Bio::Otter::Lace::OnTheFly::ResultSet::GetScript
        Bio::Otter::Lace::OnTheFly::ResultSet::Test
        Bio::Otter::Lace::OnTheFly::Runner
        Bio::Otter::Lace::OnTheFly::Runner::Transcript
        Bio::Otter::Lace::OnTheFly::TargetSeq
        Bio::Otter::Lace::OnTheFly::Transcript
        Bio::Otter::Lace::OnTheFly::Utils::ExonerateFormat
        Bio::Otter::Lace::OnTheFly::Utils::SeqList
        Bio::Otter::Lace::OnTheFly::Utils::Types
    );

    foreach my $module ( @modules ) {
        use_ok($module);
    }
}

foreach my $module ( @modules ) {
    critic_module_ok($module);
}

done_testing;

1;

# Local Variables:
# mode: perl
# End:

# EOF
