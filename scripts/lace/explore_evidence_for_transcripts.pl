#!/usr/bin/env perl

use warnings;

use strict;
use Carp;
use IO::String;
use List::Util qw(min max);

use Bio::Otter::Lace::Defaults;
use Bio::Otter::Utils::MM;

use Bio::SeqIO;
use Bio::EnsEMBL::Pipeline::SeqFetcher;
use Bio::Factory::EMBOSS;       # EMBOSS needs to be on PATH - /software/pubseq/bin/EMBOSS-5.0.0/bin
                                # To verify, check that 'wossname water' runs successfully
use Bio::AlignIO;

use Hum::Pfetch;

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
        unless (   $et eq 'ncRNA' 
                || $et eq 'EST'
                || $et eq 'Protein'
                || $et eq 'cDNA'
                || $et eq 'Genomic'
            ) {
            croak "type must be one of EST,ncRNA,Protein,cDNA,Genomic";
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
}

sub pfetch {
    my ( $id ) = @_;
    my ($hum_seq) = Hum::Pfetch::get_Sequences($id);
    unless ($hum_seq) {
        carp sprintf "Cannot pfetch '%s'!\n", $id;
        return undef;
    }
    my $seq = Bio::Seq->new(
        -seq        => $hum_seq->sequence_string,
        -display_id => $hum_seq->name,
        );
    return $seq;
}

my $mm;

sub get_accession_type {
    my $name = shift;

    $mm ||= Bio::Otter::Utils::MM->new;

    my $accession_types = $mm->get_accession_types([$name]);
    my $at = $accession_types->{$name};
    return @$at;
}

BEGIN {
    # Lower is better
    my %ANL_RANK = (
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

sub process_align_features {
    my $features_ref = shift;
    my $opts = shift;

    return undef if $opts->{max_features} and scalar(@$features_ref) > $opts->{max_features};

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

    if ($strand < 0) {
        $exons = [ reverse @$exons ];
    }

    my $exon_length   = 0;
    reportf("verbose:EA:1", "Exons (%s strand):", $strand > 0 ? "forward" : "reverse") if $dev;
    foreach my $i (0 .. $#$exons) {
        my $exon = $exons->[$i];
        $exon_length += $exon->length;
        reportf("verbose:EA:2", "%d %d-%d (%d) %d [%d]", $i, $exon->seq_region_start, $exon->seq_region_end,
                $exon->strand, $exon->length, $exon->slice) if $dev;
    }
    reportf("verbose:EA:2", "total length %d", $exon_length) if $dev;

    foreach my $fc (@$feature_chains) {

        reportf("verbose:EA:1", "Feature chain '%s' (%s): [SC:%d AL:%d %%:%.1f]",
                $fc->{hseqname}, $fc->{logic_name}, $fc->{score}, $fc->{alignment_length}, $fc->{percent_id}) if $dev;

        my $start_exon       = 0;
        my $total_overlap    = 0;
        my $exon_match_count = 0;
        my $score            = 0;

        foreach my $f (@{$fc->{features}}) {

            reportf("verbose:EA:2", "%d-%d (hs:%d) %d [SC:%d AL:%d %%:%.1f]",
                    $f->seq_region_start, $f->seq_region_end, $f->hstrand, $f->length,
                    $f->score, $f->alignment_length, $f->percent_id) if $dev;

            my $match = undef;
            my $ft;

            foreach my $i ($start_exon .. $#$exons) {

                my $exon = $exons->[$i];

                # Feature start/end are rel feature not rel seq_region or transcript/exon, so...
                #
                if (not defined $ft or $ft->slice != $exon->slice) {
                    $ft = $f->transfer($exon->slice);
                }

                if ($exon->overlaps($ft)) {
                    my $overlap = calc_overlap($exon, $f);
                    reportf("verbose:EA:3", "overlaps exon %d by %d", $i, $overlap) if $dev;
                    $match = 1;
                    ++$exon_match_count;
                    $total_overlap += $overlap;
                    $score += $f->score * $overlap / $f->alignment_length;
                } else {
                    reportf("verbose:EA:3", "does not overlap exon %d", $i) if $dev;
                    $start_exon++ if not $match;
                }
            }
        }

        $fc->{exon_match_count} = $exon_match_count;
        $fc->{total_overlap}    = $total_overlap;
        $fc->{coverage}         = $total_overlap/$exon_length*100.0;
        $fc->{exon_score}       = $score;

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
        $ele->{rank} = $i;

        my $key = $ele->{$map_key};

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

my ($factory, $comp_app);

sub get_comp_app {
    $factory ||= Bio::Factory::EMBOSS->new();
    $comp_app ||= $factory->program('water');
    return $comp_app;
}

sub compare_evidence {
    my $transcript    = shift;
    my $evidence_name = shift;
    my $evidence      = shift;
    my $hit_feature   = shift;

    my $evi_seq = pfetch($evidence_name);
    unless ($evi_seq) {
        my $msg = sprintf("Cannot pfetch sequence for '%s'", $evidence_name);
        report("all:CE:0", $msg);
        carp $msg;
        return undef;
    }

    if (    $opts->{max_length}
            and ($evi_seq->length > $opts->{max_length})
            and ($transcript->seq->length > $opts->{max_length})
        ) {
        my $msg = sprintf("Transcript %s and evidence %s both too long, skipping",
                          $transcript->stable_id, $evidence_name);
        report("all:CE:0", $msg);
        carp $msg;
        return undef;
    }

    # Compare them
    my $comp_app = get_comp_app();
    my $comp_fh = File::Temp->new();
    my $comp_outfile = $comp_fh->filename;

    my $rev_str = $evi_seq->seq;
    Bio::EnsEMBL::Utils::Sequence::reverse_comp(\$rev_str);
    my $rev_evi_seq = Bio::Seq->new(
        -seq        => $rev_str,
        -display_id => $evi_seq->display_id . ".rev",
        );

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

    $comp_app->run({-asequence => $transcript->seq,
                    -bsequence => [$evi_seq, $rev_evi_seq],
                    -outfile   => $comp_outfile,
                    -aformat   => 'srspair',
                   });

    my $alnin = Bio::AlignIO->new(-format => 'emboss',
                                  -fh     => $comp_fh);

    my @aln_results;
    while ( my $aln = $alnin->next_aln ) {
        push @aln_results, $aln;
        # process the alignment -- these will be Bio::SimpleAlign objects
        my $name = $aln->get_seq_by_pos(2)->display_id;
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
                    $evi_seq->length,
                );
        }
    }

    my $top_hit = (sort { $b->score <=> $a->score } @aln_results)[0];
    if ($top_hit == $aln_results[0]) {
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

sub process_transcript {
    my ($otter_dba, $tid, $opts) = @_;

    $transcript_adaptor ||= $otter_dba->get_TranscriptAdaptor;
    $gene_adaptor       ||= $otter_dba->get_GeneAdaptor;
    $slice_adaptor      ||= $otter_dba->get_SliceAdaptor;

    $pipe_dba        ||= Bio::Otter::Lace::PipelineDB::get_pipeline_DBAdaptor($otter_dba);
    $p_slice_adaptor ||= $pipe_dba->get_SliceAdaptor;

    my $td = $transcript_adaptor->fetch_by_dbID($tid);
    if ($td) {

        my $exons = $td->get_all_Exons;

        reportf("normal:PT:0", "Transcript %s, strand %d, exons %d", $td->stable_id, $td->strand, scalar(@$exons));

        my $gene = $gene_adaptor->fetch_by_transcript_id($tid);

        my $min_start = min($td->seq_region_start, $gene->seq_region_start);
        my $max_end   = max($td->seq_region_end,   $gene->seq_region_end);

        # Do we want to extend the region by a flanking distance in each direction?
        #
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
               $td->seq_region_start,
               $td->seq_region_end,
            );

        my $p_slice = $p_slice_adaptor->fetch_by_region($gene->coord_system_name,
                                                        $gene->seq_region_name,
                                                        $gene->start,
                                                        $gene->end);

        # Is this interesting in practice? - probably not!
        #
        my $genes = $p_slice->get_all_Genes;
        foreach my $gene (@$genes) {
            reportf("verbose:PT:1", "Got pipeline gene %s [%s]", $gene->dbID, $gene->display_id);
        }
        
        my $p_features;
        if ($opts->{logic_names}) {
            $p_features = [];
            my $p_f_seen = {};
            foreach my $logic_name ( @{$opts->{logic_names}} ) {
                feature_augment($p_features, $p_f_seen, $p_slice->get_all_DnaAlignFeatures($logic_name));
            }
        } else {
            $p_features = $p_slice->get_all_DnaAlignFeatures();
        }
        report("verbose:PT:1", "Got ", scalar @$p_features, " features");

        my $feature_chains     = process_align_features($p_features, $opts);
        my $per_exon_scoring   = exon_align_features($exons, $td->strand, $feature_chains, $opts);

        # Not sure whether to sort on exon_score or coverage.
        #
        my @per_exon_by_score = sort { $b->{exon_score} <=> $a->{exon_score} } @$per_exon_scoring;
        my $per_exon_by_score_map = make_ranked_map(\@per_exon_by_score, 'hseqname');

        my $tfe = $per_exon_by_score[0];
        if ($tfe) {
            reportf("normal:PT:1", "Top exon-scored feature: %s [Score:%d Overlap:%d Coverage:%.1f%%]",
                    $tfe->{hseqname}, $tfe->{exon_score}, $tfe->{total_overlap}, $tfe->{coverage});
        }
        
        if ($opts->{dump_seq}) {
            setup_io() unless $seqio_out;
            $seq_str_io->truncate(0);   # reset to start of $seq_str
            $seqio_out->write_seq($td->seq);
            print $seq_str;
        }

        my $all_dna_features;
        my %feature_chain_hit;

        my @evidence = @{$td->evidence_list};
        EVIDENCE: foreach my $evi (@evidence) {

            if ($opts->{evi_type}) {
                next EVIDENCE unless $evi->type eq $opts->{evi_type};
            }

            my $e_name = $evi->name;
            my @at = get_accession_type($e_name);
            reportf("verbose:PT:1", "Evidence: %s - %s [%s %s]", $e_name, $evi->type, $at[0], $at[1]);
            if ($e_name ne $at[1] and $at[1] =~ m/^$e_name/) {
                reportf("verbose:PT:1", "Adding version, %s => %s", $e_name, $at[1]);
                $e_name = $at[1];
            }
            my ($prefix, $short_name) = $e_name =~ m/^(\w+)?:?([\w\.]+)$/ ;
            $short_name ||= $e_name;

            my $hit_feature = undef;

            my $e_hit = $per_exon_by_score_map->{$short_name};
            if ($e_hit) {

                reportf("normal:PT:2",
                        "Found exon-scored feature match for %s at rank %d with %d features, logic %s",
                        $short_name, $e_hit->{rank}, $e_hit->{count}, $e_hit->{logic_name} );

                $hit_feature = $e_hit->{features}->[0];
                $feature_chain_hit{$short_name} = 1;
 
            } else {
                report("normal:PT:2", "No feature match for $short_name");

                # Do a little more digging 

              FEATURE_HUNT: {

                  # First check it's not hiding under a different logic name, if we previously narrowed
                  if ($opts->{logic_names}) {
                      $all_dna_features ||= $p_slice->get_all_DnaAlignFeatures();
                      report("verbose:PT:2", "Got ", scalar @$all_dna_features, " features using all logic names");
                      my @match_features = grep { $_->hseqname eq $short_name } @$all_dna_features;
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
                      @match_features = grep { $_->hseqname =~ /^$short_name/ } @$all_dna_features;
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
                  my $dna_features_by_name = $dna_feature_adaptor->fetch_all_by_hit_name($short_name);
                  report("verbose:PT:2", "Got ", scalar @$dna_features_by_name, " features by name");
                  if (@$dna_features_by_name) {
                      reportf("normal:PT:2", "Found %d matches by name in entire DB", scalar(@$dna_features_by_name));
                      last FEATURE_HUNT;
                  }

                  # This stanza shouldn't get hit now that we add version to $e_name above where necessary
                  $dna_features_by_name = $dna_feature_adaptor->fetch_all_by_hit_name_unversioned($short_name);
                  report("verbose:PT:2", "Got ", scalar @$dna_features_by_name, " features by name_unversioned");
                  if (@$dna_features_by_name) {
                      reportf("normal:PT:2",
                              "Found %d matches by name_unversioned in entire DB", scalar(@$dna_features_by_name));
                      last FEATURE_HUNT;
                  }

                  report("normal:PT:2", "No luck looking for feature :-(");

                } # FEATURE_HUNT
            }

            my $top_hit = compare_evidence($td, $e_name, $evi, $hit_feature);
            next EVIDENCE unless $top_hit;

        } # EVIDENCE

        # Now look at the top few feature chains and see if we've hit them.
        # If not, do SW against them, to see what the result is.
        #
      FEATURE_CHAIN: for my $i ( 0 .. min($opts->{consider_chains} - 1, $#per_exon_by_score) ) {
            my $fc = $per_exon_by_score[$i];
            if ($feature_chain_hit{$fc->{hseqname}}) {
                # Bail out as soon as we've actually seen a high-ranked feature chain
                last FEATURE_CHAIN;
            } else {
                reportf("normal:PT:1", "Evidence didn't include '%s' at rank %d", $fc->{hseqname}, $fc->{rank});
                my $top_hit = compare_evidence($td, $fc->{hseqname}, undef, $fc->{features}->[0]);
            }
        } # FEATURE_CHAIN

        printf "\n" unless $opts->{quiet};

    } else {
        carp "Cannot retrieve transcript with id %d from adaptor";
    }
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
        return undef unless $level eq 'all';
    }
    unless ($opts->{verbose}) {
        return undef if $level eq 'verbose';
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
    my $cond = shift;
    my $prefix = report_prefix($cond);
    return unless defined $prefix;

    print $prefix, @_, "\n";
}

sub reportf {
    my $cond = shift;
    my $prefix = report_prefix($cond);
    return unless defined $prefix;

    my $format = shift;
    my $msg = sprintf($format, @_);
    print $prefix, $msg, "\n";
}

__END__

=head1 NAME - explore_evidence_for_transcripts.pl

=head1 SYNOPSIS

explore_evidence_for_transcripts.pl -dataset <DATASET NAME> [-type <EVIDENCE_TYPE>] [-quiet] [-total]

=head1 DESCRIPTION

Explore evidence matching a transcript.

=head1 AUTHOR

Michael Gray B<email> mg13@sanger.ac.uk

