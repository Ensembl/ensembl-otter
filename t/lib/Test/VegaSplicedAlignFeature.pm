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

# Common test code for Bio::Vega::SplicedAlignFeature::* tests.

package Test::VegaSplicedAlignFeature;

use strict;
use warnings;

use Exporter qw(import);
use Test::More;

use Bio::Vega::Utils::GFF;

our @EXPORT_OK = qw(test_exons test_introns compare_saf_ok gff_args);

sub test_exons {
    my ($exons, $exp, $desc) = @_;
    subtest $desc => sub {
        my $i = 0;
        foreach my $exon (@$exons) {
            subtest "exon $i" => sub {
                isa_ok($exon, $exp->{package});

                my $exon_exp = $exp->{exons}->[$i];

                is($exon->vulgar_comps_string, $exon_exp->{vcs},    'vulgar_comps_string')
                    if $exon->can('vulgar_comps_string');
                is($exon->vulgar_string,       $exon_exp->{vulgar_string}, 'vulgar_string')
                    if exists $exon_exp->{'vulgar_string'};

                is($exon->start,               $exon_exp->{start},  'start');
                is($exon->end,                 $exon_exp->{end},    'end');
                is($exon->hstart,              $exon_exp->{hstart}, 'hstart');
                is($exon->hend,                $exon_exp->{hend},   'hend');

                is($exon->phase,               $exon_exp->{phase},     'phase')     if exists $exon_exp->{'phase'};
                is($exon->end_phase,           $exon_exp->{end_phase}, 'end_phase') if exists $exon_exp->{'end_phase'};

                is($exon->strand,   $exp->{strand},   'strand');
                is($exon->hstrand,  $exp->{hstrand},  'hstrand');
                is($exon->seqname,  $exp->{seqname},  'seqname');
                is($exon->hseqname, $exp->{hseqname}, 'hseqname');

                is($exon->alignment_type, 'vulgar_exonerate_components', 'alignment_type')
                    if $exon->can('alignment_type');

                done_testing;
            };
            $i++;
        }
    };
    return;
}

sub test_introns {
    my ($introns, $exp, $desc) = @_;
    subtest $desc => sub {
        my $i = 0;
        foreach my $intron (@$introns) {
            subtest "intron $i" => sub {
                isa_ok($intron, 'Bio::EnsEMBL::Intron');
                if ($intron->strand == 1) { # fwd
                    is($intron->start,  $exp->{exons}->[$i]->{end} + 1,     'start');
                    is($intron->end,    $exp->{exons}->[$i+1]->{start} - 1, 'end');
                } else { # rev
                    is($intron->start,  $exp->{exons}->[$i+1]->{end} + 1, 'start');
                    is($intron->end,    $exp->{exons}->[$i]->{start} - 1, 'end');
                }
                is($intron->strand, $exp->{strand}, 'strand');
            };
            $i++;
        }
    };
    return;
}

sub compare_saf_ok {
    my ($subj, $exp, $desc, $skips) = @_;

    my %skip;
    %skip = map { $_ => 1 } @$skips if $skips;

    subtest $desc => sub {
        foreach my $attr ( $exp->_our_attribs, 'vulgar_comps_string' ) {
            next if $skip{$attr};
            next if $attr =~ /strand$/;
            next if $attr eq 'score';
            is($subj->$attr(), $exp->$attr(), $attr);
        }
        strand_is($subj->strand,  $exp->strand,  'strand');
        strand_is($subj->hstrand, $exp->hstrand, 'hstrand');
        is($subj->score // 0, $exp->score // 0, 'score');
        done_testing;
    };
    return;
}

sub strand_is {
    my ($subj, $exp, $desc) = @_;
    $subj //= 1;
    $exp  //= 1;
    is($subj, $exp, $desc);
    return;
}

sub gff_args {
    return (
        gff_format => Bio::Vega::Utils::GFF::gff_format(3),
        gff_source => 'VSAF_test',
        );
}

1;
