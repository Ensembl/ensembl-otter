# Common test code for Bio::Vega::SplicedAlignFeature::* tests.

package Test::VegaSplicedAlignFeature;

use strict;
use warnings;

use Exporter qw(import);
use Test::More;

our @EXPORT_OK = qw(test_exons test_introns);

sub test_exons {
    my ($exons, $exp, $desc) = @_;
    subtest $desc => sub {
        my $i = 0;
        foreach my $exon (@$exons) {
            subtest "exon $i" => sub {
                isa_ok($exon, $exp->{package});

                my $exon_exp = $exp->{exons}->[$i];

                is($exon->vulgar_comps_string, $exon_exp->{vcs},    'vulgar_comps_string') if $exon->can('vulgar_comps_string');

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

1;
