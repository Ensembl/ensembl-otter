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

package Deletion;

use InterimExon;
use StatMsg;
use Length;

use Utils qw(print_exon);


###############################################################################
# process_delete
#
# processes a deletion in an exon
###############################################################################

sub process_delete {
  my $support = shift;
  my $cdna_del_pos_ref  = shift;
  my $del_len           = shift;
  my $exon        = shift;
  my $transcript  = shift;
  my $entire_delete = shift;

  my $del_start = $$cdna_del_pos_ref + 1;
  my $del_end   = $del_start + $del_len - 1;

  $support->log((($entire_delete) ? 'entire ' : '')."delete ($del_len) at " .
       $$cdna_del_pos_ref."\n", 5);
  $support->log("BEFORE cds: ". $transcript->cdna_coding_start.'-'.
       $transcript->cdna_coding_end."\n", 5);
  $support->log("BEFORE del_start = $del_start\n", 5);

  # sanity check, deletion should be completely in
  # or adjacent to exon boundaries
  if(!$entire_delete && ($del_start < $exon->cdna_start - 1 ||
			 $del_start > $exon->cdna_end + 1)) {

    $support->log_error("Unexpected: deletion is outside of exon boundary\n" .
          "     del_start       = $del_start\n" .
          "     cdna_exon_start =". $exon->cdna_start .
          "     cdna_exon_end   =". $exon->cdna_end."\n", 5);
  }

  # break delete into composite parts and deal with each part seperately

  #
  # deal with five prime UTR portion of delete
  #
  if($del_start < $transcript->cdna_coding_start) {
    my $utr_del_len;

    if($del_end >= $transcript->cdna_coding_start) {
      $utr_del_len = $transcript->cdna_coding_start - $del_start;
    } else {
      $utr_del_len = $del_len;
    }

    process_five_prime_utr_delete($support, $cdna_del_pos_ref, $utr_del_len,
				  $exon, $transcript);

    # take away the processed part of the deletion
    $del_start = $$cdna_del_pos_ref + 1;
    $del_len   -= $utr_del_len;
    $del_end   = $del_start + $del_len - 1;
  }

  if($del_len == 0) {
    # no deletion left
    $exon->fix_phase($transcript) if(!$entire_delete);
    return;
  }

  #
  # deal with CDS portion of delete
  #
  if($del_end >= $transcript->cdna_coding_start &&
     $del_start <= $transcript->cdna_coding_end) {

    my $cds_del_len;

    if($del_end > $transcript->cdna_coding_end) {
      $cds_del_len = $transcript->cdna_coding_end - $del_start + 1;
    } else {
      $cds_del_len = $del_len;
    }

    process_cds_delete($support, $cdna_del_pos_ref, $cds_del_len, $exon,
                      $transcript, $entire_delete);

    # take away the processed part of the deletion
    # the cdna start is in the same place because
    $del_start += $$cdna_del_pos_ref + 1;
    $del_len  -= $cds_del_len;
    $del_end   = $del_start + $del_len - 1;
  }

  if($del_len == 0) {
    # no deletion left
    $exon->fix_phase($transcript) if(!$entire_delete);;
    return;
  }

  #
  # deal with 3prime portion of delete
  #

  # sanity check:
  if($del_start <= $transcript->cdna_coding_end) {
    $support->log_error("Unexpected. 3' UTR delete starts before coding end.", 5);
  }

  process_three_prime_utr_delete($support, $cdna_del_pos_ref, $del_len, $exon,
				 $transcript);

  $exon->fix_phase($transcript) if(!$entire_delete);

  return;
}

###############################################################################
# process_five_prime_utr_delete
#
# processes a deletion in the five prime utr of a transcript
###############################################################################

sub process_five_prime_utr_delete {
  my $support = shift;
  my $cdna_del_pos_ref = shift;
  my $del_len          = shift;
  my $exon             = shift;
  my $transcript       = shift;

  $support->log("delete ($del_len) in 5' utr\n", 5);

  # shift up the CDS
  $transcript->move_cdna_coding_start(-$del_len);
  $transcript->move_cdna_coding_end(-$del_len);

  # create a status message and add it to the exon
  my $code = StatMsg::EXON | StatMsg::DELETE | StatMsg::FIVE_PRIME |
             StatMsg::UTR | Length::length2code($del_len);
  $exon->add_StatMsg(StatMsg->new($code));

  return;
}

###############################################################################
# process_three_prime_utr_delete
#
# processes a deletion in the three prime utr of a transcript
###############################################################################

sub process_three_prime_utr_delete {
  my $support = shift;
  my $cdna_del_pos_ref = shift;
  my $del_len          = shift;
  my $exon             = shift;
  my $transcript       = shift;

  #do not have to do anything...
  $support->log("delete ($del_len) in 3' utr\n", 5);

  # create a status message and add it to the exon
  my $code = StatMsg::EXON | StatMsg::DELETE | StatMsg::THREE_PRIME |
             StatMsg::UTR | Length::length2code($del_len);
  $exon->add_StatMsg(StatMsg->new($code));

  return;
}

###############################################################################
# process_cds_delete
#
# processes a deletion in the cds of a transcript
###############################################################################

sub process_cds_delete {
  my $support = shift;
  my $cdna_del_pos_ref = shift;
  my $del_len          = shift;
  my $exon             = shift;
  my $transcript       = shift;
  my $entire_delete    = shift;

  $support->log("delete ($del_len) in cds\n", 5);

  my $del_start = $$cdna_del_pos_ref + 1;
  my $del_end   = $del_start + $del_len - 1;

  my $code = StatMsg::EXON | StatMsg::DELETE | StatMsg::CDS |
             Length::length2code($del_len);

  my $frameshift = $del_len % 3;


  #
  # case 1: delete is all of CDS
  #
  if($del_start == $transcript->cdna_coding_start &&
     $del_end   == $transcript->cdna_coding_end) {
    $support->log("delete ($del_len) is all of cds\n", 5);

    $code |= StatMsg::ENTIRE;

    # move up CDS end to account for CDS deletion
    $transcript->move_cdna_coding_end(-$del_len);
  }

  #
  # case 2: delete is at start of CDS
  #
  elsif($del_start == $transcript->cdna_coding_start) {
    $support->log("delete ($del_len) at start of cds\n", 5);

    $code |= StatMsg::FIVE_PRIME;

    # move up CDS end to account for CDS deletion
    $transcript->move_cdna_coding_end(-$del_len);

    if($frameshift) {
      $code |= StatMsg::FRAMESHIFT if($frameshift);

      # move down CDS start to put reading frame back (shrink CDS)
      $support->log("shifting cds start to restore reading frame\n", 5);
      $transcript->move_cdna_coding_start(3 - $frameshift);
    }
  }

  #
  # case 3: delete is at end of CDS
  #
  elsif($del_end == $transcript->cdna_coding_end) {
    $support->log("delete ($del_len) at end of cds\n", 5);

    $code |= StatMsg::THREE_PRIME;

    # move up CDS end to account for CDS deletion
    $transcript->move_cdna_coding_end(-$del_len);

    if($frameshift) {
      $code |= StatMsg::FRAMESHIFT if($frameshift);

      # move up CDS end to put reading frame back (shrink CDS)
      $support->log("shifting cds end to restore reading frame\n", 5);
      $transcript->move_cdna_coding_end($frameshift-3);
    }
  }

  #
  # case 4: delete is in middle of CDS
  #
  elsif($del_end   > $transcript->cdna_coding_start &&
        $del_start < $transcript->cdna_coding_end) {
    $support->log("delete ($del_len) in middle of cds\n", 5);

    $code |= StatMsg::MIDDLE;

    # move up CDS end to account for CDS deletion
    $transcript->move_cdna_coding_end(-$del_len);

    if($frameshift && !$entire_delete) {
      $support->log("BEFORE CDS DELETE:\n", 5);
      print_exon($exon, $transcript);

      $code |= StatMsg::FRAMESHIFT if($frameshift);

      # this is going to require splitting the exon
      # to make a frameshift deletion

      #first exon is going to end right before deletion
      my $first_len  = $del_start - $exon->cdna_start;
      my $intron_len = 3 - $frameshift;

      #reduce the length of the CDS by the length of the new intron
      $transcript->move_cdna_coding_end(-$intron_len);

      # the next match that is added to the cdna position will have too much
      # sequence because we used part of the sequence to create the frameshift
      # intron, compensate by reducing cdna position by intron len
      $$cdna_del_pos_ref -= $intron_len;

      $support->log("introducing frameshift intron ($intron_len) " .
            "to maintain reading frame\n", 5);

      # very short exons can be entirely consumed by the intron
      if($intron_len == $exon->length) {
        # still adjust this 0 length intron, because its length
        # is used in transcript splitting calculations
        $exon->cdna_end($exon->cdna_end - $intron_len);
        if($exon->strand == 1) {
          $exon->end($exon->end - $intron_len);
        } else {
          $exon->start($exon->start + $intron_len);
        }
        $code |= StatMsg::ALL_INTRON;
        $exon->fail(1);
      }
      elsif($intron_len > $exon->length) {
        $code |= StatMsg::CONFUSED | StatMsg::ALL_INTRON;

        # still adjust this negative length exon b/c its length is used
        # in transcript splitting calculations
        $exon->cdna_end($exon->cdna_end - $intron_len);
        if($exon->strand == 1) {
          $exon->end($exon->end - $intron_len);
        } else {
          $exon->start($exon->start + $intron_len);
        }

        $exon->fail(1);
      }
      elsif($first_len + $intron_len >= $exon->length) {
        # we may have encountered a delete at the very end of the exon
        # in this case we have to take the intron out of the end of this exon
        # since we are not creating a second one

        if($exon->strand == 1) {
          $exon->end($exon->end - $intron_len);
        } else {
          $exon->start($exon->start + $intron_len);
        }
        $exon->cdna_end($exon->cdna_end - $intron_len);
      } else {
        # second exon is going to start right after 'frameshift intron'

        if($exon->strand == 1) {
          # end the current exon at the beginning of the deletion
          # watch out though, because we may be at the very beginning of
          # the exon in which case we do not want to create one

          if($first_len) {
            my $first_exon = InterimExon->new;

            # Copy the original exon and adjust the coords as necessary
            # Note that these exons will share stat msgs which is what
            # we want.
            %{$first_exon} = %{$exon};
            $first_exon->cdna_end($exon->cdna_start + $first_len - 1);
            $first_exon->end($first_exon->start + $first_len - 1);
            $transcript->add_Exon($first_exon);

            $support->log("FIRST EXON:\n", 5);
            $support->log("$first_exon, $transcript", 5);
            $exon->add_StatMsg(StatMsg->new(StatMsg::EXON | StatMsg::SPLIT));

            $exon->cdna_start($first_exon->cdna_end + 1);
            $first_exon->set_split_phases($exon, $transcript);
          }

          # start next exon after new intron
          $exon->start($exon->start + $first_len + $intron_len);
          $exon->cdna_end($exon->cdna_end - $intron_len);
        } else {
          if($first_len) {
            my $first_exon = InterimExon->new;

            # copy the original exon and adjust the coords as necessary
            # these exons will share stat msgs
            %{$first_exon} = %{$exon};
            $first_exon->cdna_end($exon->cdna_start + $first_len - 1);
            $first_exon->start($exon->end - $first_len + 1);
            $transcript->add_Exon($first_exon);

            $support->log("FIRST EXON:\n", 5);
            print_exon($first_exon, $transcript);
            $exon->add_StatMsg(StatMsg->new(StatMsg::EXON | StatMsg::SPLIT));

            $exon->cdna_start($first_exon->cdna_end + 1);

            $first_exon->set_split_phases($exon, $transcript);
          }

          # start next exon after new intron
          $exon->end($exon->end - ($first_len + $intron_len));
          $exon->cdna_end($exon->cdna_end - $intron_len);
        }
      }

      $support->log("AFTER CDS DELETE:\n", 5);
      print_exon($exon, $transcript);
    }
  }

  # sanity check:
  else {
    $support->log_error("Unexpected: CDS delete appears to be outside of CDS:\n" .
         "  del_start = $del_start\n".
         "  del_end   = $del_end\n" .
         "  cdna_coding_start = ".$transcript->cdna_coding_start . "\n".
         "  cdna_coding_end   = ".$transcript->cdna_coding_end . "\n", 5);
  }

  $exon->add_StatMsg(StatMsg->new($code));

  return;
}





1;
