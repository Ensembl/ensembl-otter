=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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

package Test::Bio::Vega::Utils::ExonPhase;

use Test::Class::Most
    parent     => 'OtterTest::Class';

# This is a bit clunky, we could do with a non-OO parent class to handle critic and use_ok
# more cleanly.

BEGIN { __PACKAGE__->use_imports( [ qw( exon_phase_EnsEMBL_to_Ace exon_phase_Ace_to_EnsEMBL ) ] ) };

# because not OO, we need to also import here into this test class
BEGIN { use Bio::Vega::Utils::ExonPhase @{__PACKAGE__->use_imports()} }

sub build_attributes { return; } # none

sub setup       { return; }  # don't let OtterTest::Class do its OO stuff
sub constructor { return; }  # --"--

sub t_exon_phase_EnsEMBL_to_Ace : Tests {
    my @results = map { exon_phase_EnsEMBL_to_Ace($_) } ( -1 .. 4 );
    is_deeply(\@results, [ undef, 1, 3, 2, undef, undef ], 'all okay');
    return;
}

sub t_exon_phase_Ace_to_EnsEMBL : Tests {
    my @results = map { exon_phase_Ace_to_EnsEMBL($_) } ( -1 .. 4 );
    is_deeply(\@results, [ undef, undef, 0, 2, 1, undef ], 'all okay');
    return;
}

1;
