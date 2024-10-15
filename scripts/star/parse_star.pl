#!/usr/bin/env perl
# Copyright [2018-2024] EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


### parse_star.pl

use strict;
use warnings;
use Getopt::Long qw{ GetOptions };

{
    my $offset = 0;
    my $usage = sub { exec('perldoc', $0) };
    GetOptions(
        'offset=i'  => \$offset,
    ) or $usage->();

    while (<>) {
        next if /^@/;
        chomp;
        my ($hit_name
          , $binary_flags
          , $chr_name
          , $chr_start
          , $map_quality
          , $cigar
          , $rnext
          , $pnext
          , $tlen
          , $hit_sequence
          , $hit_quality
          , @optional_flags
        ) = split /\t/, $_;


        # Parse the optional flags
        my ($chr_strand, $score, $edit_distance);
        foreach my $attr (@optional_flags) {
            my ($FG, $type, $value) = split /:/, $attr;
            if ($FG eq 'jM') {
                my @splices = $value =~ /,(-?\d+)/g;
                my $strand_vote = 0;
                foreach my $n (@splices) {
                    next unless $n > 0; # Value of 0 signifies non-consensus splice; -1 no splice sites.
                    # Odd numbers are forward strand splice sites, even are reverse
                    $strand_vote += $n % 2 ? 1 : -1;
                }

                if ($strand_vote == 0) {
                    # No splice info, so we don't know which genomic strand we're on
                    $chr_strand = 0;
                }
                elsif ($strand_vote > 1) {
                    $chr_strand = 1;
                }
                else {
                    $chr_strand = -1;
                }
            }
            elsif ($FG eq 'AS') {
                $score = $value;
            }
            elsif ($FG eq 'NM') {
                $edit_distance = $value;
            }
        }

        my $flipped_hit = $binary_flags & 16;
        my ($hit_strand);
        if ($chr_strand == 0) {
            # No information about chr strand from splice sites
            $hit_strand = 1;
            $chr_strand = $flipped_hit ? -1 : 1;
        }
        else {
            # A flipped hit to a reverse strand gene is a match to the forward strand of the hit
            $hit_strand = $chr_strand * ($flipped_hit ? -1 : 1);
        }

        my @cigar_fields = $cigar =~ /(\d+)(\D)/g;
        if ($chr_strand == -1) {
            # Reverse the CIGAR, keeping the pairs of OP + INT together.
            my $limit = @cigar_fields - 2;  # Last pair would be a no-op
            for (my $i = 0; $i < $limit; $i += 2) {
                splice(@cigar_fields, $i, 0, splice(@cigar_fields, -2, 2));
            }
        }

        my @vulgar_fields;
        my $hit_start      = 1;
        my $hit_aln_length = 0;
        my $chr_aln_length = 0;
        my $hit_pad_length = 0; # Needed for percent identity
        my $hit_del_length = 0; # Needed for hit coverage
        my $hit_length = length($hit_sequence);
        for (my $i = 0; $i < @cigar_fields; $i += 2) {
            my ($len, $op) = @cigar_fields[ $i, $i + 1 ];
            if ($op eq 'M') {
                push @vulgar_fields, 'M', $len, $len;
                $chr_aln_length += $len;
                $hit_aln_length += $len;
            }
            elsif ($op eq 'N') {
                push @vulgar_fields, 5, 0, 2, 'I', 0, $len - 4, 3, 0, 2;
                $chr_aln_length += $len;
            }
            elsif ($op eq 'I') {
                push @vulgar_fields, 'G', $len, 0;
                $hit_aln_length += $len;
                $hit_del_length += $len;    # Will not contribute to hcoverage
            }
            elsif ($op eq 'D') {
                push @vulgar_fields, 'G', 0, $len;
                $chr_aln_length += $len;
                $hit_pad_length += $len;    # Will add to span of alignment
            }
            elsif ($op eq 'S') {
                # Soft clipping - clipped sequence is present in SAM
                if ($i == 0) {
                    $hit_start += $len;
                }
            }
            elsif ($op eq 'H') {
                # Hard clipping - clipped sequence not present in SAM
                $hit_length += $len;
            }
            else {
                die "Unexpected SAM CIGAR element: '$len$op'";
            }
        }
        my $hit_end = $hit_start + $hit_aln_length - 1;
        my $chr_end = $chr_start + $chr_aln_length - 1;

        # The total span of the gapped alignment (not including introns) minus the edit distance
        my $percent_identity = sprintf "%.3f", 100 * (1 - ($edit_distance / ($hit_pad_length + $hit_aln_length)));
        
        my $hit_coverage     = sprintf "%.3f", 100 * (($hit_aln_length - $hit_del_length) / $hit_length);

        if ($hit_strand == -1) {
            my $new_hit_start = $hit_length - $hit_end   + 1;
            $hit_end          = $hit_length - $hit_start + 1;
            $hit_start = $new_hit_start;
        }

        my $pattern = "%18s  %-s\n";

        print STDERR "\n";
        printf STDERR $pattern, 'seq_region_start',  $offset + $chr_start;
        printf STDERR $pattern, 'seq_region_end',    $offset + $chr_end;
        printf STDERR $pattern, 'seq_region_strand', $chr_strand;
        printf STDERR $pattern, 'hit_start',         $hit_start;
        printf STDERR $pattern, 'hit_end',           $hit_end;
        printf STDERR $pattern, 'hit_strand',        $hit_strand;
        printf STDERR $pattern, 'hit_name',          $hit_name;
        printf STDERR $pattern, 'perc_ident',        $percent_identity;
        printf STDERR $pattern, 'hcoverage',         $hit_coverage;
        printf STDERR $pattern, 'alignment_string',  "@vulgar_fields";
        
        

        # print STDERR join("\t", $chr_name, $chr_strand, $hit_name, $hit_start, $hit_end, $hit_strand, "@vulgar_fields"), "\n";
    }
}



__END__

=head1 NAME - parse_star.pl

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

    SELECT seq_region_start
      , seq_region_end
      , seq_region_strand
      , hit_start
      , hit_end
      , hit_strand
      , SUBSTR(hit_name, 5) AS hit_name
      , perc_ident
      , hcoverage
      , alignment_string
    FROM dna_spliced_align_feature
    ORDER BY hit_name;

  seq_region_start  108454675
    seq_region_end  108459309
 seq_region_strand  -1
         hit_start  2
           hit_end  666
        hit_strand  1
          hit_name  BB_FWD
        perc_ident  99.85
         hcoverage  
  alignment_string  M 28 28 G 1 0 M 19 19 G 0 1 M 37 37 5 0 2 I 0 384 3 0 2 M 160 160 5 0 2 I 0 3097 3 0 2 M 182 182 5 0 2 I 0 478 3 0 2 M 127 127 G 1 0 M 110 110

  seq_region_start  108454675
    seq_region_end  108459309
 seq_region_strand  -1
         hit_start  3
           hit_end  667
        hit_strand  -1
          hit_name  BB_REV
        perc_ident  99.85
         hcoverage  
  alignment_string  M 28 28 G 1 0 M 19 19 G 0 1 M 37 37 5 0 2 I 0 384 3 0 2 M 160 160 5 0 2 I 0 3097 3 0 2 M 182 182 5 0 2 I 0 478 3 0 2 M 127 127 G 1 0 M 110 110

  seq_region_start  108486660
    seq_region_end  108487682
 seq_region_strand  1
         hit_start  2
           hit_end  752
        hit_strand  1
          hit_name  CF_FWD
        perc_ident  100
         hcoverage  
  alignment_string  M 35 35 G 1 0 M 45 45 G 0 1 M 148 148 5 0 2 I 0 83 3 0 2 M 218 218 5 0 2 I 0 95 3 0 2 M 97 97 5 0 2 I 0 82 3 0 2 M 207 207

  seq_region_start  108486660
    seq_region_end  108487682
 seq_region_strand  1
         hit_start  1
           hit_end  751
        hit_strand  -1
          hit_name  CF_REV
        perc_ident  100
         hcoverage  
  alignment_string  M 35 35 G 1 0 M 45 45 G 0 1 M 148 148 5 0 2 I 0 83 3 0 2 M 218 218 5 0 2 I 0 95 3 0 2 M 97 97 5 0 2 I 0 82 3 0 2 M 207 207

  seq_region_start  108473265
    seq_region_end  108473936
 seq_region_strand  1
         hit_start  3
           hit_end  675
        hit_strand  1
          hit_name  SGL_FWD
        perc_ident  100
         hcoverage  
  alignment_string  M 77 77 G 1 0 M 595 595

  seq_region_start  108473265
    seq_region_end  108473936
 seq_region_strand  -1
         hit_start  1
           hit_end  673
        hit_strand  1
          hit_name  SGL_REV
        perc_ident  100
         hcoverage  
  alignment_string  M 595 595 G 1 0 M 77 77
