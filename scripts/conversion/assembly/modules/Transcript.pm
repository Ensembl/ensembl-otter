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


use strict;
use warnings;

package Transcript;

#
# A set of utility methods for dealing with Interim transcripts
# and creating real transcripts out of them.
#


use StatMsg;
use InterimTranscript;
use Utils qw(print_exon);
use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::Exon;

use constant MAX_INTRON_LEN => 2e6;

#these are long genes that have been OKeyed by Havana
my %long_genes = map {$_,1 } qw(OTTHUMG00000150663 OTTHUMG00000086753 OTTHUMG00000086796 OTTHUMG00000030300 OTTMUSG00000022667 OTTMUSG00000031222 OTTMUSG00000026145 OTTHUMG00000166726);

#Long genes that we've seen before
my %long_genes_seen_as_bad = map {$_,1} qw(OTTDARG00000019998);

#
# sanity checks the interim exons, and splits this
# interim transcript into parts
#

sub check_iexons {
  my $support = shift;
  my $itranscript = shift;
  my $gsi = shift;
  my $itranscript_array = shift;

  my $prev_start            = undef;
  my $prev_end              = undef;
  my $transcript_seq_region = undef;
  my $transcript_strand     = undef;
  my $failed_transcript     = {};

  my $tsi = $itranscript->stable_id;

  $support->log_verbose("checking exons for $tsi\n", 4);

  my $first = 1;
  my $fail_flag = 0;

 EXON:
  foreach my $iexon (@{ $itranscript->get_all_Exons }) {
    if ($iexon->fail || $iexon->is_fatal) {
      $support->log("Exon ".$iexon->stable_id." failed to transfer. Skipping transcript $tsi.\n", 3);
      $failed_transcript = {
        'reason'  => 'exon failure',
        'exon_id' => $iexon->stable_id};
      $fail_flag = 1;
      last EXON;
    }

    # sanity check: expect first exon to have cdna_start = 1
    if($first && $iexon->cdna_start != 1) {
      print_exon($support, $iexon);
      $support->log_error("Unexpected ($tsi): first exon does not have cdna_start = 1\n", 6);
    }
    $first = 0;

    # sanity check: start must be less than or equal to end
    if ($iexon->end < $iexon->start) {
      $support->log("Unexpected ($tsi): exon start less than end: ".$iexon->stable_id.": ".$iexon->start.'-'.$iexon->end."\n", 6);
    }

    # sanity check: cdna length must equal length
    if($iexon->length != $iexon->cdna_end - $iexon->cdna_start + 1) {
      $support->log_warning("Unexpected: exon cdna length != exon length: ".
			     $iexon->stable_id.": ".$iexon->start.'-'.$iexon->end .
			     $iexon->cdna_start.'-'.$iexon->cdna_end."\n", 6);
    }

    if (!defined($transcript_seq_region)) {
      $transcript_seq_region = $iexon->seq_region;
    }

    # watch out for exons that come in the wrong order
    if((defined($prev_end) && $iexon->strand == 1 &&
	  $prev_end > $iexon->start) ||
	    (defined($prev_start) && $iexon->strand == -1 &&
	       $prev_start < $iexon->end)) {
      $support->log("Exon ".$iexon->stable_id." in wrong order. Skipping transcript $tsi.\n", 3);
      $failed_transcript = {
        'reason'  => 'exon order',
        'exon_id' => $iexon->stable_id};
      $fail_flag = 1;
      last EXON;
    }

    if (!defined($transcript_strand)) {
      $transcript_strand = $iexon->strand;
    } elsif ($transcript_strand != $iexon->strand) {
      $support->log("Exon ".$iexon->stable_id." on wrong strand. Skipping transcript $tsi.\n", 3);
      $failed_transcript = {
        'reason'  => 'exon strand',
        'exon_id' => $iexon->stable_id};
      $fail_flag = 1;
      last EXON;
    }

    # watch out for extremely long introns
    my $intron_len = 0;

    if(defined($prev_start)) {
      if($iexon->strand == 1) {
	$intron_len = $iexon->start - $prev_end + 1;
      } else {
	$intron_len = $prev_start - $iexon->end + 1;
      }
    }

    if($intron_len > MAX_INTRON_LEN) {
      if ($long_genes{$gsi}) {
	$support->log("Long intron in transcript but gene OKeyed by Havana\n",5);
      }
      elsif ($long_genes_seen_as_bad{$gsi}) {
	$support->log("Long intron in transcript known to be bad\n",5);
        $failed_transcript = {
          'reason'    => 'known bad long intron'};
        $fail_flag = 1;
	last EXON;
      }
      else {
	$support->log_warning("Very long intron ($intron_len bp) in gene that has not been OKeyed. Have a look at transcript $tsi (gene $gsi) and delete if neccesary - probably will be! Then add it to ignore list\n", 2);
      }
    }

    $prev_end = $iexon->end;
    $prev_start = $iexon->start;
  }
  
  $itranscript_array ||= [];

  #
  # if there exons left after all the splitting,
  # then add this transcript to the array
  #
  unless ($fail_flag) {
    my $total_exons = scalar(@{ $itranscript->get_all_Exons });
    if ($total_exons > 0) {
      push @$itranscript_array, $itranscript;
    } else {
      $support->log_verbose("no exons left in transcript\n", 4);
    }
  }
  return $itranscript_array,$failed_transcript;
}


#
# creates proper ensembl transcripts and exons from interim transcripts
# and exons.
#
sub make_Transcript {
  my $support = shift;
  my $itrans = shift;
  my $E_sa = shift;

  my $transcript = Bio::EnsEMBL::Transcript->new;
  $transcript->stable_id($itrans->stable_id);
  $transcript->version($itrans->version);
  $transcript->biotype($itrans->biotype);
  $transcript->status($itrans->status);
  $transcript->analysis($itrans->analysis);
  $transcript->description($itrans->description);
  $transcript->created_date($itrans->created_date);
  $transcript->modified_date($itrans->modified_date);
  $transcript->add_Attributes(@{ $itrans->transcript_attribs });
  $transcript->add_supporting_features(@{ $itrans->get_all_TranscriptSupportingFeatures });

  #this is where is should go I reckon!
#	$transcript->display_xref($itrans->display_xref);

  $support->log_verbose("making final transcript for ".$itrans->stable_id."\n", 4);

  # the whole translation may have been deleted
  # discard translation if mrna is less than a codon in length
  my $translation;
  if(!$itrans->cdna_coding_start or ($itrans->cdna_coding_end - $itrans->cdna_coding_start + 1 < 3)) {
    $translation = undef;
  } else {
    $translation = Bio::EnsEMBL::Translation->new;
    $transcript->translation($translation);
  }

  # protein features
  my @protein_features;
  if (defined($transcript->translation)) {
    foreach my $pf (@{ $itrans->get_all_ProteinFeatures }) {
      $pf->score(0) unless ($pf->score);
      $pf->percent_id(0) unless($pf->percent_id);
      $pf->p_value(0) unless ($pf->p_value);
#           $pf->dbID(undef);
      push @protein_features, $pf;
    }
  }
  foreach my $iexon (@{ $itrans->get_all_Exons }) {
    my $E_slice = $E_sa->fetch_by_seq_region_id($iexon->seq_region);

    my $exon = Bio::EnsEMBL::Exon->new
      (-START         => $iexon->start,
       -END           => $iexon->end,
       -STRAND        => $iexon->strand,
       -PHASE         => $iexon->start_phase,
       -END_PHASE     => $iexon->end_phase,
       -STABLE_ID     => $iexon->stable_id,
       -VERSION       => $iexon->version,
       -CREATED_DATE  => $iexon->created_date,
       -MODIFIED_DATE => $iexon->modified_date,
       -SLICE         => $E_slice);

    # supporting evidence
    $exon->add_supporting_features(@{ $iexon->get_all_SupportingFeatures });
    $transcript->add_Exon($exon);

    # see if this exon is the start or end exon of the translation
    if ($translation) {
      if ($iexon->cdna_start <= $itrans->cdna_coding_start &&
            $iexon->cdna_end   >= $itrans->cdna_coding_start) {
        my $translation_start =
          $itrans->cdna_coding_start - $iexon->cdna_start + 1;
        $translation->start_Exon($exon);
        $translation->start($translation_start);
      }

      if ($iexon->cdna_start <= $itrans->cdna_coding_end &&
            $iexon->cdna_end   >= $itrans->cdna_coding_end) {
        my $translation_end =
          $itrans->cdna_coding_end - $iexon->cdna_start + 1;
        $translation->end_Exon($exon);
        $translation->end($translation_end);
      }
    }
  }

  if($translation && !$translation->start_Exon) {
    $support->log_warning("Could not find translation start exon in transcript.\n", 5);
    $support->log_warning("FIRST EXON:\n", 6);
    print_exon($support, $itrans->get_all_Exons->[0]);
    $support->log_warning("LAST EXON:\n", 6);
    print_exon($support, $itrans->get_all_Exons->[-1], $itrans);
    $support->log_error("Unexpected: Could not find translation start exon in transcript\n", 6);
  }
  if($translation && !$translation->end_Exon) {
    $support->log_warning("Could not find translation end exon in transcript.\n", 5);
    $support->log_warning("FIRST EXON:\n", 6);
    print_exon($support, $itrans->get_all_Exons->[0]);
    $support->log_warning("LAST EXON:\n", 6);
    print_exon($support, $itrans->get_all_Exons->[-1], $itrans);
    $support->log_error("Unexpected: Could not find translation end exon in transcript\n", 6);
  }

  return ($transcript, \@protein_features);
}

1;
