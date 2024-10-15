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


use warnings;

use strict;
use Carp;
use IO::String;
use List::Util qw(min max);
use Readonly;

use Bio::Otter::Lace::Defaults;
use Bio::Otter::Lace::PipelineDB;

use Bio::Vega::Enrich::SliceGetAllAlignFeatures; # Enriched Bio::EnsEMBL::Slice::get_all_DnaDnaAlignFeatures 
                                                 # (with hit descriptions)
use Bio::Vega::Evidence::Types qw( evidence_type_valid_all );
use Bio::Vega::Utils::Align;
use Bio::Vega::Utils::Evidence qw(get_accession_type reverse_seq);

use Bio::SeqIO;

use Hum::ClipboardUtils qw(magic_evi_name_match);
use Hum::Pfetch;

use Evi::CollectionFilter;
use Evi::EviCollection;

package Evi::EviCollection;

# Should be in EviCollection but let's play here for now

sub new {
    my $pkg = shift;
    my $self = bless {}, $pkg;
    $self->{_collection} = {};  # hash{by_analysis} of lists of chains
    $self->{_name2chains} = {}; # sublists of chains indexed by name
    return $self;
}

package main; ## no critic (Modules::ProhibitMultiplePackages)

Readonly my $MAX_UNDERLAP        => 10;
Readonly my $MAX_TRAIL           => 10;
Readonly my $MAX_OVERSIZE_INSERT => 10;

{
    # Lower is better
    Readonly my %ANL_RANK => (
        Est2genome_human     => 1,
        Est2genome_human_raw => 2,
        );

    sub anl_rank {
        my $logic_name = shift;
        my $rank = $ANL_RANK{$logic_name};
        return $rank || 1e6;
    }

    sub feature_anl_rank {
        my $f = shift;
        return anl_rank($f->analysis->logic_name);
    }
}

my $opts;

{
    my $dataset_name = undef;
    $opts = {
        total => 0,
        quiet => 0,
        verbose => 0,
        dump_seq => 0,
        dump_features => 0,
        dump_exon_matches => 0,
        evi_type => undef,
        max_length => undef,
        max_features => undef,
        logic_names => undef,
        consider_chains => 3,
    };

    my $usage = sub { exec('perldoc', $0) };
    # This do_getopt() call is needed to parse the otter config files
    # even if you aren't giving any arguments on the command line.
    Bio::Otter::Lace::Defaults::do_getopt(
        'h|help!'       => $usage,
        'dataset=s'     => \$dataset_name,
        'quiet!'        => \$opts->{quiet},
        'verbose!'      => \$opts->{verbose},
        'total!'        => \$opts->{total},
        'dumpseq!'      => \$opts->{dump_seq},
        'dumpfeatures!' => \$opts->{dump_features},
        'dumpexonmatches+'=>\$opts->{dump_exon_matches},
        'type=s'        => \$opts->{evi_type},
        'maxlength=i'   => \$opts->{max_length},
        'maxfeatures=i' => \$opts->{max_features},
        'logicnames=s'  => \$opts->{logic_names},
        ) or $usage->();

    $usage->() unless $dataset_name;

    if (my $et = $opts->{evi_type}) {
        unless (evidence_type_valid_all($et)) {
            my $valid = join(',', @Bio::Vega::Evidence::Types::ALL);
            croak "type must be one of $valid";
        }
    }

    if ($opts->{quiet} and not $opts->{total}) {
        carp "Using -quiet but not -total - no output will be produced!";
    }

    if ($opts->{logic_names}) {
        $opts->{logic_names} = [ split(',', $opts->{logic_names}) ];
    }

    {
        my %evitype2logic = (
            'EST' => ['Est2genome_human','Est2genome_human_raw'],
            );

        if ($opts->{evi_type} and not $opts->{logic_names}) {
            $opts->{logic_names} = $evitype2logic{$opts->{evi_type}};
            if ($opts->{logic_names}) {
                carp("Logic names set to '", join(',', @{$opts->{logic_names}}),
                     "' for evidence type '", $opts->{evi_type}, "'");
            } else {
                carp("No logic name translation for evidence type '", $opts->{evi_type}, "'");
            }
        }
    }

    # Client communicates with otter HTTP server
    my $cl = Bio::Otter::Lace::Defaults::make_Client();
    
    # DataSet interacts directly with an otter database
    my $ds = $cl->get_DataSet_by_name($dataset_name);
    my $otter_dba = $ds->get_cached_DBAdaptor;

    my $where = "";
    my @args = ();
    if ($opts->{evi_type}) {
        $where = "AND e.type = ?";
        push @args, $opts->{evi_type};
    }
    my $list_transcripts = $otter_dba->dbc->prepare(qq{
        SELECT DISTINCT
                t.transcript_id
        FROM
                transcript t
           JOIN gene g USING (gene_id)
           JOIN evidence e ON t.transcript_id = e.transcript_id
           JOIN seq_region_attrib sra ON t.seq_region_id = sra.seq_region_id
        WHERE
                t.is_current = 1
            AND g.source = 'havana'
            -- Make sure it is on a writeable seq_region
            AND sra.attrib_type_id = (SELECT attrib_type_id FROM attrib_type WHERE code = 'write_access')
            AND sra.value = 1
            $where
        ORDER BY t.transcript_id
    });
    $list_transcripts->execute(@args);

    my $count = 0;
    while (my ($tid) = $list_transcripts->fetchrow()) {
        ++$count;
        reportf("verbose:ML:0", "TID: %10d", $tid );
        process_transcript($otter_dba, $tid, $opts);
    }
    reportf("all:ML:0", "Total: %d", $count) if $opts->{total};

}

# Used in process_transcript() if $opts{dump_seq} - SORT OUT VIA SUBROUTINES
#
my ($seq_str, $seq_str_io, $seqio_out);

sub setup_io {
    $seq_str_io = IO::String->new(\$seq_str);
    $seqio_out = Bio::SeqIO->new(-format => 'Fasta',
                                 -fh     => $seq_str_io );
    return;
}

sub pfetch {
    my ( $id ) = @_;
    my ($hum_seq) = Hum::Pfetch::get_Sequences($id);
    unless ($hum_seq) {
        carp sprintf "Cannot pfetch '%s'!\n", $id;
        return;
    }
    my $seq = Bio::Seq->new(
        -seq        => $hum_seq->sequence_string,
        -display_id => $hum_seq->name,
        );
    return $seq;
}

sub process_align_features {
    my $features_ref = shift;
    my $opts = shift;

    return if $opts->{max_features} and scalar(@$features_ref) > $opts->{max_features};

    my %hseq_anl_acc = ();
    my @flat_hseq_anl_acc = ();

    my $count = 0;

    my @features = sort { 
        feature_anl_rank($a) <=> feature_anl_rank($b)
                              ||
        $a->hseqname         cmp $b->hseqname
                              ||
        $a->start            <=> $b->start 
    } @{$features_ref};

  FEATURE: foreach my $feature ( @features ) {

        my $hseqname = $feature->hseqname;

        if ($opts->{evi_type} and not $opts->{logic_names}) {
            my ($f_type, $f_ver) = get_accession_type($hseqname);
            $f_type ||= "";
            if ($f_type ne $opts->{evi_type}) {
                reportf("normal:PF:1", "Skipping %s, type is '%s'", $hseqname, $f_type);
                next FEATURE;
            }
        }

        my $anid = $feature->analysis->dbID;

        my $acc = $hseq_anl_acc{$hseqname}->{$anid};
        unless (defined $acc) {
            $acc = $hseq_anl_acc{$hseqname}->{$anid} = { hseqname    => $hseqname,
                                                         analysis_id => $anid, 
                                                         logic_name  => $feature->analysis->logic_name, 
                                                         count       => 0,
                                                         score       => 0,
                                                         alignment_length => 0,
                                                         identical   => 0,
                                                         features    => []
                                                       };
            push @flat_hseq_anl_acc, $acc;
        }

        ++$acc->{count};
        $acc->{score}  += $feature->score;
        $acc->{alignment_length} += $feature->alignment_length;
        $acc->{identical} += ($feature->alignment_length * $feature->percent_id / 100.0);
        $acc->{percent_id} = $acc->{identical} / $acc->{alignment_length} * 100.0;

        push @{$acc->{features}}, $feature;

        reportf("all:PF:1", "%d %s %s", $feature->dbID, $hseqname, make_align_fingerprint($feature))
            if $opts->{dump_features};

        ++$count;
    }

    reportf("verbose:PF:1", "Processed %d features into %d feature chains", $count, scalar @flat_hseq_anl_acc);

    return \@flat_hseq_anl_acc;
}

sub calc_overlap {
    my $a = shift;
    my $b = shift;
    return min($a->seq_region_end, $b->seq_region_end) - max($a->seq_region_start, $b->seq_region_start) + 1;
}

# Side-effects warning - adds elements to @$feature_chains members
#
sub exon_align_features {
    my $exons = shift;
    my $strand = shift;
    my $feature_chains = shift;
    my $opts = shift;

    my $dem = $opts->{dump_exon_matches};
    my $dev = ($dem and $dem > 1);
    my $dep = ($dem and $dem > 2);

    if ($strand < 0) {
        $exons = [ reverse @$exons ];
    }

    my $exon_length   = 0;
    reportf("verbose:EA:1", "Exons (%s strand):", $strand > 0 ? "forward" : "reverse") if $dev;
    foreach my $i (0 .. $#$exons) {
        my $exon = $exons->[$i];
        $exon_length += $exon->length;
        reportf("verbose:EA:2", "%d %d-%d (%d) %d [%s]", $i, $exon->seq_region_start, $exon->seq_region_end,
                $exon->strand, $exon->length, $exon->slice->display_id) if $dev;
    }
    reportf("verbose:EA:2", "total length %d", $exon_length) if $dev;

    foreach my $fc (@$feature_chains) {

        reportf("verbose:EA:1", "Feature chain '%s' (%s): [SC:%d AL:%d %%:%.1f] FL:%d",
                $fc->{hseqname}, $fc->{logic_name}, $fc->{score}, $fc->{alignment_length}, $fc->{percent_id},
                $fc->{features}->[0]->get_HitDescription->hit_length,
               ) if $dev;

        my $start_exon       = 0;
        my $total_overlap    = 0;
        my $exon_match_count = 0;
        my @exon_match_map   = ();
        my $score            = 0;
        my $penalty          = 0;

        foreach my $f (@{$fc->{features}}) {

            reportf("verbose:EA:2", "%d-%d (hs:%d) %d [SC:%d AL:%d %%:%.1f]",
                    $f->seq_region_start, $f->seq_region_end, $f->hstrand, $f->length,
                    $f->score, $f->alignment_length, $f->percent_id) if $dev;

            my $match = undef;

            foreach my $i ($start_exon .. $#$exons) {

                my $exon = $exons->[$i];
                if ($exon->overlaps($f)) {

                    my $overlap = calc_overlap($exon, $f);
                    reportf("verbose:EA:3", "overlaps exon %d by %d (%d-%d hcoords %d-%d)",
                            $i, $overlap, $f->seq_region_start, $f->seq_region_end, $f->hstart, $f->hend) if $dev;
                    if ($match) {
                        report("verbose:EA:3", "FEATURE SPANS EXONS") if $dev;
                        $penalty += 1000;
                    }
                    $match = 1;
                    ++$exon_match_count;
                    push @exon_match_map, $i;
                    $total_overlap += $overlap;
                    $score += $f->score * $overlap / $f->alignment_length;

                } else {
                    reportf("verbose:EA:3", "does not overlap exon %d", $i) if $dep;
                    $start_exon++ if not $match;
                }
            }
        }

        $fc->{exon_match_count} = $exon_match_count;
        $fc->{exon_match_map}   = \@exon_match_map;
        $fc->{total_overlap}    = $total_overlap;
        $fc->{coverage}         = $total_overlap/$exon_length*100.0;
        $fc->{exon_score}       = $score;
        $fc->{penalty}          = $penalty;

        if ($dev) {
            reportf("verbose:EA:1", " => %d/%d exons, overlap length %d, coverage %.1f%%, score %d",
                    $exon_match_count, scalar(@$exons), $total_overlap, $fc->{coverage}, $score);
        } elsif ($dem) {
            reportf("verbose:EA:1", "FC '%s' (%s): %d/%d exons, overlap length %d, coverage %.1f%%, score %d",
                    $fc->{hseqname}, $fc->{logic_name}, 
                    $exon_match_count, scalar(@$exons), $total_overlap, $fc->{coverage}, $score);
        }
    }

    reportf("verbose:EA:1", "Processed exon matches for %d feature chains", scalar(@$feature_chains));

    return $feature_chains;
}

# Side-effects warning - adds 'rank' element to @$sorted members
#
sub make_ranked_map {
    my $sorted = shift;
    my $map_key = shift;

    my $map = {};

    for my $i ( 0..$#$sorted ) {

        my $ele = $sorted->[$i];
        # WARNING - MAKES ASSUMPTIONS about structure of $ele
        $ele->{_otter_rank} = $i;

        my $key;
        if (eval { $ele->can($map_key) }) {
            $key = $ele->$map_key;
        } else {
            $key = $ele->{$map_key};
        }

        # Only point to top-ranked hit for key
        #
        unless ($map->{$key}) {
            $map->{$key} = $ele;
        }

    }

    return $map;
}

sub make_align_fingerprint {
    my $feature = shift;
    my $mini_fp = make_mini_fingerprint($feature);
    return sprintf("%s %.1f %s", $mini_fp, $feature->percent_id(), $feature->cigar_string());
}

sub make_mini_fingerprint {
    my $feature = shift;
    return sprintf("%d-%d (%+d)\t=> %d-%d (%+d)\t: %d",
                   $feature->hstart(), $feature->hend(), $feature->hstrand(),
                   $feature->start(),  $feature->end(),  $feature->strand(),
                   $feature->score(),
        );
}

sub feature_augment {
    my ($f_list, $hseqname_seen, $n_list) = @_;
    my $n = 0;
    foreach my $f ( @$n_list ) {
        my $hseqname    = $f->hseqname;
        my $fingerprint = make_mini_fingerprint($f);
        my $key         = join(':', $hseqname, $fingerprint);

        next if $hseqname_seen->{$key};

        push(@$f_list, $f);
        $hseqname_seen->{$key} = 1;
        ++$n;
    }
    return $n;
}

{
    my ($aligner);

    sub get_aligner {
        $aligner ||= Bio::Vega::Utils::Align->new;
        return $aligner;
    }
}

sub compare_fetched_features_to_ref {
    my $ref_seq = shift;
    my $feature_list = shift;
    my $fetcher = shift;
    my $do_reverse = shift;

    my @feature_seqs;

  FEATURE: foreach my $f_name (@$feature_list) {

        my $f_seq = &$fetcher($f_name, $ref_seq);
        next FEATURE unless $f_seq;

        push @feature_seqs, $f_seq;

        if ($do_reverse) {
            push @feature_seqs, reverse_seq($f_seq);
        }
  }

    # Compare them
    my $aligner = get_aligner();
    my $aln_results = $aligner->compare_feature_seqs_to_ref( $ref_seq, \@feature_seqs );

    return $aln_results;
}

sub pfetch_feature_max_len {
    my $feature_name = shift;
    my $ref_seq = shift;

    my $f_seq = pfetch($feature_name);
    unless ($f_seq) {
        rcarpf("all:CE:0", "Cannot pfetch sequence for '%s'", $feature_name);
        return;
    }
    
    if (    $opts->{max_length}
            and ($f_seq->length > $opts->{max_length})
            and ($ref_seq->length > $opts->{max_length})
        ) {
        rcarpf("all:CE:0", "Ref seq %s and feature %s both too long, skipping",
               $ref_seq->display_id, $feature_name);
        return;
    }

    return $f_seq;
}

sub score_align_features {
    my $transcript = shift;
    my $feature_list = shift;

    my $n_features = scalar @$feature_list;
    reportf("verbose:SA:1", "Aligning %d features to %s", $n_features, $transcript->stable_id);

    my @best_direction_hits;

    my $chunk_size = 100;
    for (my $i = 0; $i < $n_features; $i += $chunk_size) {

        my $limit = min($i+$chunk_size-1, $n_features-1);
        reportf("verbose:SA:2", "Features %d .. %d", $i, $limit);
        my @slice = @$feature_list[$i .. $limit];

        my $aln_results = compare_fetched_features_to_ref($transcript->seq,
                                                          \@slice,
                                                          \&pfetch_feature_max_len,
                                                          1);

      ALIGN: while (@$aln_results) {
            my $fwd = shift @$aln_results;
            my $rev = shift @$aln_results;
        
            my $name = $fwd->feature_seq->display_id;
            my $best;

            if ($fwd->score >= $rev->score) {
                reportf("verbose:SA:2", "Best match for %s is forward", $name);
                $fwd->direction(1);
                $best = $fwd;
            } else {
                reportf("verbose:SA:2", "Best match for %s is reverse", $name);
                $rev->direction(-1);
                $best = $rev;
            }
            
            my $ul = $best->underlap_length($transcript->strand);
            if ($ul) {
                reportf("verbose:SA:3", "Underlaps by %d", $ul);
            }

            my $trl = $best->trailing_length($transcript->strand);
            my $polyA = "";
            if ($trl) {
                my $trl_seq = $best->trailing_feature_seq($transcript->strand);
                # What constitutes a poly-A tail? Here one or more trailing As together
                if ($trl_seq =~ /^A+$/) {
                    $polyA = " - looks like poly(A) tail: $trl_seq";
                } 
                reportf("verbose:SA:3", "Trails by %d%s", $trl, $polyA);
            }

            my $max_os = 0;
            if (my @os_inserts = $best->oversize_inserts) {
                my $n_os = scalar @os_inserts;
                $max_os = length( (sort {$b cmp $a} @os_inserts)[0] );
                reportf("verbose:SA:3", "Oversize inserts: %d, largest %d", $n_os, $max_os);
            }

            if ($ul > $MAX_UNDERLAP) {
                reportf("all:SA:2:", "Dropping %s, underlap %d > %d", $name, $ul, $MAX_UNDERLAP);
                next ALIGN;
            }
            if ($trl > $MAX_TRAIL and not $polyA) {
                reportf("all:SA:2:", "Dropping %s, trail %d > %d", $name, $trl, $MAX_TRAIL);
                next ALIGN;
            }
            if  ($max_os > $MAX_OVERSIZE_INSERT) {
                reportf("all:SA:2:", "Dropping %s, max os insert %d > %d", $name, $max_os, $MAX_OVERSIZE_INSERT);
                next ALIGN;
            }

            $best->id($name);
            push @best_direction_hits, $best;
        }
    }

    return [sort {$b->score <=> $a->score} @best_direction_hits];
}

sub compare_evidence {
    my $transcript    = shift;
    my $evidence_name = shift;
    my $evidence      = shift;
    my $hit_feature   = shift;
    my $results_map   = shift;

    my ($msg, $exp);
    if ($hit_feature) {
        if ($hit_feature->hstrand == $transcript->strand) {
            $msg = "Feature hit and transcript strands match    - expecting forward match";
            $exp = 1;
        } else {
            $msg = "Feature hit and transcript strands mismatch - expecting reverse match";
            $exp = -1;
        }
    } else {
        $msg = "No hit feature - no match prediction";
    }
    report("normal:CE:2", $msg);

    my $top_hit = $results_map->{$evidence_name};
    unless ($top_hit) {
        my $aln_results = compare_fetched_features_to_ref($transcript->seq,
                                                          [$evidence_name],
                                                          \&pfetch_feature_max_len,
                                                          1);

        $aln_results->[0]->direction(1);
        $aln_results->[1]->direction(-1);

        foreach my $aln (@$aln_results) {
            # process the alignment -- these will be Bio::Vega::SimpleAlign objects
            my $name = $aln->feature_seq->display_id;
            if ($opts->{verbose}) {
                reportf("verbose:CE:3", "feature: %-15s : score: %8.1f, length: %5d, ident: %5.1f%%",
                        $name,
                        $aln->score,
                        $aln->length,
                        $aln->percentage_identity,
                    );
            } elsif (not $opts->{quiet}) {
                reportf("normal:CE:3", "%s,%s,%s,%.1f,%d,%.1f,%d,%d",
                        $transcript->stable_id,
                        $name,
                        $evidence ? $evidence->type : '-',
                        $aln->score,
                        $aln->length,
                        $aln->percentage_identity,
                        $transcript->seq->length,
                        $aln->feature_seq->length,
                    );
            }
        }

        $top_hit = (sort { $b->score <=> $a->score } @$aln_results)[0];
    }

    if ($top_hit->direction > 0) {
        report("verbose:CE:2", "Top match on forward");
        if ($exp) {
            if ($exp == 1) {
                report("normal:CE:2", "Match on forward as expected");
            } else {
                report("all:CE:2", "MATCH ON FORWARD, EXPECTING REVERSE");
            }
        }
    } else {
        report("verbose:CE:2", "Top match on reverse");
        if ($exp) {
            if ($exp == -1) {
                report("normal:CE:2", "Match on reverse as expected");
            } else {
                report("all:CE:2", "MATCH ON REVERSE, EXPECTING FORWARD");
            }
        }
    }
    
    return $top_hit;
}

my ($transcript_adaptor, $gene_adaptor, $slice_adaptor, $dna_feature_adaptor);
my ($pipe_dba, $p_slice_adaptor);

my $evi_filter = [
    Evi::SortCriterion->new('Analysis','analysis',
                            [],'alphabetic','is','Est2genome'),
    Evi::SortCriterion->new('Supported introns', 'trans_supported_introns',
                            [], 'numeric','descending',1),
    Evi::SortCriterion->new('Supported junctions', 'trans_supported_junctions',
                            [], 'numeric','descending'),
    Evi::SortCriterion->new('Supported % of transcript','transcript_coverage',
                            [], 'numeric','descending'),
    Evi::SortCriterion->new('Dangling ends (bases)','contrasupported_length',
                            [], 'numeric','ascending',10),
    ];

sub report_ec_hit {
    my $report_control = shift;
    my $ec_hit = shift;
    my $ts = shift;
    reportf($report_control,
            "Found EviChain feature match for %s at rank %d with %d features, logic %s",
            $ec_hit->name, $ec_hit->{_otter_rank}, scalar @{$ec_hit->afs_lp}, $ec_hit->analysis );
    reportf($report_control,
            "Supported introns: %d, junctions: %d; TS cov %.1f%%; contra len %d",
            $ec_hit->trans_supported_introns($ts),
            $ec_hit->trans_supported_junctions($ts),
            $ec_hit->transcript_coverage($ts),
            $ec_hit->contrasupported_length($ts));
    return;
}

sub process_transcript {
    my ($otter_dba, $tid, $opts) = @_;

    $transcript_adaptor ||= $otter_dba->get_TranscriptAdaptor;
    $gene_adaptor       ||= $otter_dba->get_GeneAdaptor;
    $slice_adaptor      ||= $otter_dba->get_SliceAdaptor;

    $pipe_dba        ||= Bio::Otter::Lace::PipelineDB::get_pipeline_DBAdaptor($otter_dba);
    $p_slice_adaptor ||= $pipe_dba->get_SliceAdaptor;

    my $td = $transcript_adaptor->fetch_by_dbID($tid);
    if ($td) {

        my $gene = $gene_adaptor->fetch_by_transcript_id($tid);

        my $min_start = min($td->seq_region_start, $gene->seq_region_start);
        my $max_end   = max($td->seq_region_end,   $gene->seq_region_end);

        # Do we want to extend the region by a flanking distance in each direction?
        #
        my $p_slice = $p_slice_adaptor->fetch_by_region($gene->coord_system_name,
                                                        $gene->seq_region_name,
                                                        $gene->start,
                                                        $gene->end);

        # Make sure transcript has loaded exons before transferring it
        $td->get_all_Exons;

        my $p_td = $td->transfer($p_slice);

        my $exons = $p_td->get_all_Exons;

        reportf("normal:PT:0", "Transcript %s, strand %d, exons %d", $p_td->stable_id, $p_td->strand, scalar(@$exons));

        # DEBUG
#        $DB::single = 1 if $p_td->stable_id eq 'OTTHUMT00000076914';
#        $DB::single = 1 if $p_td->stable_id eq 'OTTHUMT00000077344';
#        $DB::single = 1 if $p_td->stable_id eq 'OTTHUMT00000077359';

        # This really wants to move before $p_slice fetch, left here to allow comparison of outputs
        # It doesn't even reflect reality!
        reportf("verbose:PT:1",
               "Fetching from pipeline DB: %s [%s] @ %s %s from %d to %d (g %d to %d) (ts %d to %d)",
               $gene->stable_id,
               $gene->external_name || '-',
               $gene->coord_system_name,
               $gene->seq_region_name,
               $min_start,
               $max_end,
               $gene->seq_region_start,
               $gene->seq_region_end,
               $p_td->seq_region_start,
               $p_td->seq_region_end,
            );

        # Is this interesting in practice? - probably not!
        #
        my $genes = $p_slice->get_all_Genes;
        foreach my $gene (@$genes) {
            reportf("verbose:PT:1", "Got pipeline gene %s [%s]", $gene->dbID, $gene->display_id);
        }
        
        my $p_features;
        my $evi_coll = Evi::EviCollection->new;
        $evi_coll->rna_analyses_lp([]);     # shouldn't be necessary
        $evi_coll->protein_analyses_lp([]); # shouldn't be necessary
        if ($opts->{logic_names}) {
            $p_features = [];
            my $p_f_seen = {};
            foreach my $logic_name ( @{$opts->{logic_names}} ) {
                my $features = $p_slice->get_all_DnaDnaAlignFeatures($logic_name);
                feature_augment($p_features, $p_f_seen, $features);
                $evi_coll->add_collection($features, $logic_name);
                push @{$evi_coll->rna_analyses_lp}, $logic_name;
            }
        } else {
            $p_features = $p_slice->get_all_DnaDnaAlignFeatures();
            # FIXME - what to do with $evi_coll
        }
        report("verbose:PT:1", "Got ", scalar @$p_features, " features");
        if ($opts->{max_features} and scalar(@$p_features) > $opts->{max_features}) {
            reportf("all:PT:1", "Skipping further processing as more than %d features", $opts->{max_features});
            return;
        }

        my $feature_chains     = process_align_features($p_features, $opts);
        my $per_exon_scoring   = exon_align_features($exons, $p_td->strand, $feature_chains, $opts);

        # Not sure whether to sort on exon_score or coverage.
        #
        my @per_exon_by_score = sort { $a->{penalty}    <=> $b->{penalty}
                                                        ||
                                       $b->{exon_score} <=> $a->{exon_score} } @$per_exon_scoring;
        my $per_exon_by_score_map = make_ranked_map(\@per_exon_by_score, 'hseqname');

        my $tfe = $per_exon_by_score[0];
        if ($tfe) {
            reportf("normal:PT:1",
                    "Top exon-scored feature: %s [Score:%d Overlap:%d Coverage:%.1f%% Exons: %d (%s)]",
                    $tfe->{hseqname},
                    $tfe->{exon_score}, $tfe->{total_overlap}, $tfe->{coverage}, $tfe->{exon_match_count},
                    join(',', @{$tfe->{exon_match_map}}) );
        }

        my $cfs = Evi::CollectionFilter->new(
            'Explore Evidence (EST)',
            $evi_coll,
            $evi_filter,
            $evi_filter,
            1,
            );
        $cfs->current_transcript($p_td);
        my $cfs_results = $cfs->results_lp;
        reportf("normal:PT:1", "Got %d results from CollectionFilter", scalar @$cfs_results);
        my $cfs_map;
        if (@$cfs_results) {
            reportf("normal:PT:1", "Top CF result: %s", $cfs_results->[0]->name);
            $cfs_map = make_ranked_map($cfs_results, 'name');
        }

        my $align_results = score_align_features($p_td, [keys %$per_exon_by_score_map]);
        reportf("normal:PT:1", "Got %d results from score_align_features", scalar @$align_results);
        my $align_results_map;
        if (@$align_results) {
            reportf("normal:PT:1", "Top SAR result: %s", $align_results->[0]->id);
            $align_results_map = make_ranked_map($align_results, 'id');
        }

        if ($opts->{dump_seq}) {
            setup_io() unless $seqio_out;
            $seq_str_io->truncate(0);   # reset to start of $seq_str
            $seqio_out->write_seq($p_td->seq);
            print $seq_str;
        }

        my $all_dna_features;
        my %feature_chain_hit;

        my @evidence = @{$p_td->evidence_list};
        EVIDENCE: foreach my $evi (@evidence) {

            if ($opts->{evi_type}) {
                next EVIDENCE unless $evi->type eq $opts->{evi_type};
            }

            my $e_name = $evi->name;
            my ($e_prefix, $e_short_name, $e_ver) = magic_evi_name_match($e_name);
            $e_name = $e_ver ? sprintf('%s.%s', $e_short_name, $e_ver) : $e_short_name;

            my ($a_type, $a_ver) = get_accession_type($e_name);
            reportf("verbose:PT:1", "Evidence: %s - %s [%s %s]", $evi->name, $evi->type, $a_type, $a_ver);
            if ($e_name ne $a_ver and $a_ver =~ m/^$e_name/) {
                reportf("verbose:PT:1", "Adding version, %s => %s", $e_name, $a_ver);
                $e_name = $a_ver;
            }

            # $e_name may have been updated, so...
            ($e_prefix, $e_short_name, $e_ver) = magic_evi_name_match($e_name);
            $e_name = $e_ver ? sprintf('%s.%s', $e_short_name, $e_ver) : $e_short_name;

            my $hit_feature = undef;

            my $saf_hit = $align_results_map ? $align_results_map->{$e_name} : undef;
            if ($saf_hit) {
                reportf("normal:PT:2", "Found align-scored hit for %s at rank %d, score %f, length %d, ident %f",
                        $e_name, $saf_hit->{_otter_rank},
                        $saf_hit->score, $saf_hit->length, $saf_hit->percentage_identity,
                    );
                $feature_chain_hit{$e_name} = 1;
            }

            my $cfs_hit = $cfs_map ? $cfs_map->{$e_name} : undef;
            if ($cfs_hit) {
                report_ec_hit("normal:PT:2", $cfs_hit, $p_td);
                $hit_feature = $cfs_hit->get_first_exon; # may get overridden below
#                $feature_chain_hit{$e_name} = 1;
            }

            my $e_hit = $per_exon_by_score_map->{$e_name};
            if ($e_hit) {
                reportf("normal:PT:2",
                        "Found exon-scored feature match for %s at rank %d with %d features, logic %s",
                        $e_name, $e_hit->{_otter_rank}, $e_hit->{count}, $e_hit->{logic_name} );
                reportf("normal:PT:2", "Exons: %d (%s)", $e_hit->{exon_match_count}, 
                        join(',', @{$e_hit->{exon_match_map}}));

                $hit_feature = $e_hit->{features}->[0];
#                $feature_chain_hit{$e_name} = 1;
            }

            unless ($e_hit or $cfs_hit or $saf_hit) {
                report("normal:PT:2", "No feature match for $e_name");

                # Do a little more digging 

              FEATURE_HUNT: {

                  # First check it's not hiding under a different logic name, if we previously narrowed
                  if ($opts->{logic_names}) {
                      $all_dna_features ||= $p_slice->get_all_DnaDnaAlignFeatures();
                      report("verbose:PT:2", "Got ", scalar @$all_dna_features, " features using all logic names");
                      my @match_features = grep { $_->hseqname eq $e_name } @$all_dna_features;
                      if (@match_features) {
                          reportf("normal:PT:2",
                                  "Found %d exact matches using all logic names", scalar(@match_features));
                          if ($opts->{verbose}) {
                              foreach my $feature (@match_features) {
                                  reportf("verbose:PT:3", "%s : %s",
                                          $feature->hseqname, $feature->analysis->logic_name);
                              }
                          }
                          last FEATURE_HUNT;
                      }
                      # This stanza shouldn't get hit now that we add version to $e_name above where necessary
                      @match_features = grep { $_->hseqname =~ /^$e_name/ } @$all_dna_features;
                      if (@match_features) {
                          reportf("normal:PT:2",
                                  "Found %d partial matches using all logic names", scalar(@match_features));
                          if ($opts->{verbose}) {
                              foreach my $feature (@match_features) {
                                  reportf("verbose:PT:3", "%s : %s",
                                          $feature->hseqname, $feature->analysis->logic_name);
                              }
                          }
                          last FEATURE_HUNT;
                      }
                  }

                  # Next lookup by name
                  $dna_feature_adaptor ||= $pipe_dba->get_DnaAlignFeatureAdaptor;
                  my $dna_features_by_name = $dna_feature_adaptor->fetch_all_by_hit_name($e_name);
                  report("verbose:PT:2", "Got ", scalar @$dna_features_by_name, " features by name");
                  if (@$dna_features_by_name) {
                      reportf("normal:PT:2", "Found %d matches by name in entire DB", scalar(@$dna_features_by_name));
                      last FEATURE_HUNT;
                  }

                  # This stanza shouldn't get hit now that we add version to $e_name above where necessary
                  $dna_features_by_name = $dna_feature_adaptor->fetch_all_by_hit_name_unversioned($e_name);
                  report("verbose:PT:2", "Got ", scalar @$dna_features_by_name, " features by name_unversioned");
                  if (@$dna_features_by_name) {
                      reportf("normal:PT:2",
                              "Found %d matches by name_unversioned in entire DB", scalar(@$dna_features_by_name));
                      last FEATURE_HUNT;
                  }

                  report("normal:PT:2", "No luck looking for feature :-(");

                } # FEATURE_HUNT
            }

            my $top_hit = compare_evidence($p_td, $e_name, $evi, $hit_feature, $align_results_map);
            next EVIDENCE unless $top_hit;

        } # EVIDENCE

        # Now look at the top few feature chains and see if we've hit them.
        # If not, do SW against them, to see what the result is.
        #
      FEATURE_CHAIN: for my $i ( 0 .. min($opts->{consider_chains} - 1, $#per_exon_by_score) ) {
            my $fc = $per_exon_by_score[$i];
            if ($feature_chain_hit{$fc->{hseqname}}) {
                # DON'T # Bail out as soon as we've actually seen a high-ranked feature chain
                #       last FEATURE_CHAIN;
            } else {
                reportf("normal:PT:1", "Evidence didn't include '%s' at rank %d", $fc->{hseqname}, $fc->{_otter_rank});
                if (my $ec = $cfs_map->{$fc->{hseqname}}) {
                    report_ec_hit("normal:PT:1", $ec, $p_td);
                }
                my $top_hit = compare_evidence($p_td, $fc->{hseqname}, undef, $fc->{features}->[0], $align_results_map);
            }
        } # FEATURE_CHAIN

        printf "\n" unless $opts->{quiet};

    } else {
        carp "Cannot retrieve transcript with id %d from adaptor";
    }
    return;
}

# Rational output of results
#
#   opts:  quiet  neither verbose
# all       Y      Y       Y
# normal    N      Y       Y
# verbose   N      N       Y

sub report_prefix {
    my $cond = shift;
    my ($level, $context, $indent) = split(':', $cond);

    if ($opts->{quiet}) {
        return unless $level eq 'all';
    }
    unless ($opts->{verbose}) {
        return if $level eq 'verbose';
    }

    if ($opts->{context}) {
        my $n = 4*($indent+1);
        my $prefix_format = "%-${n}s";
        return sprintf($prefix_format, $context);
    } else {
        return $indent ? ' ' x (4*$indent) : '';
    }
}

sub report {
    my ($cond, @args) = @_;

    my $prefix = report_prefix($cond);
    return unless defined $prefix;

    print $prefix, @args, "\n";
    return;
}

sub reportf {
    my ($cond, $format, @args) = @_;

    my $prefix = report_prefix($cond);
    return unless defined $prefix;

    my $msg = sprintf($format, @args);
    print $prefix, $msg, "\n";
    return;
}

sub rcarpf {
    my ($cond, $format, @args) = @_;

    my $msg = sprintf($format, @args);
    report($cond, $msg);
    carp $msg;
    return;
}

__END__

=head1 NAME - explore_evidence_for_transcripts.pl

=head1 SYNOPSIS

explore_evidence_for_transcripts.pl -dataset <DATASET NAME> [-type <EVIDENCE_TYPE>] [-quiet] [-total]

=head1 DESCRIPTION

Explore evidence matching a transcript.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

