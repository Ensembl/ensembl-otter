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

use strict;
use warnings;

package Utils;

use Exporter;
use vars qw(@ISA @EXPORT_OK);
@ISA = qw(Exporter);

@EXPORT_OK = qw(print_exon print_coords print_translation print_three_phase_translation);

#
# prints debugging info
#
sub print_exon {
    my $support = shift;
    my $exon = shift;
    my $tr = shift;

    if (!$exon) {
        throw("Exon undefined");
    }

    $support->log($exon->stable_id, 6);

    $support->log("cdna_start = ".$exon->cdna_start, 7)
        if(defined($exon->cdna_start));

    $support->log("cdna_end = ". $exon->cdna_end, 7)
        if(defined($exon->cdna_end));

    $support->log("start = ". $exon->start, 7)
        if(defined($exon->start));

    $support->log("end = ". $exon->end, 7)
        if(defined($exon->end));

    $support->log("strand = ". $exon->strand, 7)
        if(defined($exon->strand));

    if($exon->fail) {
        $support->log("FAILED", 7);
    }

    if($tr) {
        $support->log("TRANSCRIPT:", 7);
        $support->log("cdna_coding_start = ". $tr->cdna_coding_start, 7);
        $support->log("cdna_coding_end   = ". $tr->cdna_coding_end. "\n", 7);
    }

    return;
}


sub print_coords {
    my $support = shift;
    my $cs = shift;

    foreach my $c (@$cs) {
        if($c->isa('Bio::EnsEMBL::Mapper::Gap')) {
            $support->log("GAP ". $c->length, 7);
        } else {
            $support->log($c->start. '-'. $c->end. ' ('.$c->strand.")", 7);
        }
    }
}


sub print_translation {
    my $support = shift;
    my $tl = shift;

    $support->log("TRANSLATION", 6);

    if(!$tl) {
    $support->log("undef", 7);
    return;
    }

    if($tl->start_Exon) {
    $support->log("start exon = ", $tl->start_Exon->stable_id, 7);
    } else {
    $support->log("start exon = undef", 7);
    }

    if($tl->end_Exon) {
        $support->log("end exon = ", $tl->end_Exon->stable_id, 7);
    } else {
        $support->log("end exon = undef", 7);
    }

    if(defined($tl->start)) {
        $support->log("start = ", $tl->start, 7);
    } else {
        $support->log("start = undef", 7);
    }

    if(defined($tl->end)) {
        $support->log("end = ", $tl->end, 7);
    } else {
        $support->log("end = undef", 7);
    }

    return;
}


sub print_three_phase_translation {
    my $support = shift;
    my $transcript = shift;

    return if(!$transcript->translation);

    my $orig_phase = $transcript->start_Exon->phase;

    foreach my $phase (0,1,2) {
        $support->log("======== Phase $phase translation: ", 6);
        $transcript->start_Exon->phase($phase);
        $support->log("Peptide: " . $transcript->translate->seq . "\n\n===============", 6);
    }

    $transcript->start_Exon->phase($orig_phase);

    return;
}


1;
