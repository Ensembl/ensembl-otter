=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

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

package Bio::Otter::ServerAction::Region;

use strict;
use warnings;

use Readonly;
use Try::Tiny;
use Lingua::EN::Inflect qw( A NUMWORDS );

use Bio::Otter::Lace::CloneSequence;
use Bio::Vega::ContigInfo;
use Bio::Vega::SliceLockBroker;
use Bio::Vega::Region;
use Bio::Vega::Tiler;
use Bio::Vega::Utils::Attribute qw( get_name_Attribute_value );
use base 'Bio::Otter::ServerAction';

=head1 NAME

Bio::Otter::ServerAction::Region - server requests on a region

=head1 CONSTRUCTOR

=cut

Readonly my @SLICE_REQUIRED_PARAMS => qw(
    dataset
    cs
    csver
    chr
    start
    end
);


=head2 new_with_slice

=cut

sub new_with_slice {
    my ($pkg, $server) = @_;

    my $self = $pkg->new($server);

    my $params = $server->require_arguments(@SLICE_REQUIRED_PARAMS);
    my $slice = $self->_get_requested_slice($params);
    $self->slice($slice);

    return $self;
}

sub _get_requested_slice {
    my ($self, $params) = @_;

    my $strand  = 1;

    return $self->server->otter_dba->get_SliceAdaptor->fetch_by_region(
        $params->{cs},
        $params->{chr},
        $params->{start},
        $params->{end},
        $strand,
        $params->{csver}
        );
}


=head1 METHODS

=head2 get_assembly_dna

=cut

sub get_assembly_dna {
    my $self = shift;

    my $slice = $self->slice;
    my $output = {
        dna => $slice->seq,
    };

    return $output;
}


=head2 get_region

=cut

sub get_region {
    my $self = shift;

    my $slice = $self->slice;

    my $region = Bio::Vega::Region->new_from_otter_db(
        slice         => $slice,
        server_action => $self,
        );

    my $serialised_region = $self->serialise_region($region);
    return $serialised_region;
}


=head2 DE_region

Server-side generation of the "DE line" text, previously available in
the EditWindow::Clone window and generated client-side by
C<<$Assembly->generate_description_for_clone>> .

=cut

sub DE_region {
    my ($self) = @_;

    my $slice = $self->slice;

    my $GA   = $slice->adaptor->db->get_GeneAdaptor;
    my @loci = @{ $GA->fetch_all_by_Slice_untruncated($slice) };
    for (my $i = 0; $i < @loci;) {
        if ($loci[$i]->source eq 'havana') {
            $i++;
        }
        else {
            # Remove non-havana genes
            splice @loci, $i, 1;
        }
    }

    my @keywords;
    my $novel_gene_count      = 0;
    my $part_novel_gene_count = 0;
    my @DEline;

    # Loop through the loci in 5' -> 3' order
    foreach my $gene (sort {$a->start <=> $b->start} @loci) {
        my $gene_result = $self->_DE_gene($gene,
                                          $slice->length,
                                          sub { $novel_gene_count++ },
                                          sub { $part_novel_gene_count++ }
            );
        next unless $gene_result;
        push @keywords, @{$gene_result->{keywords}};
        push @DEline,   $gene_result->{DE_line} if $gene_result->{DE_line};
    }

    if ($novel_gene_count) {
        if ($novel_gene_count == 1) {
            push @DEline, "a novel gene";
        }
        else {
            push @DEline, NUMWORDS($novel_gene_count) . " novel genes";
        }
    }

    if ($part_novel_gene_count) {
        if ($part_novel_gene_count == 1) {
            push @DEline, "part of a novel gene";
        }
        else {
            push @DEline, "parts of " . NUMWORDS($part_novel_gene_count) . " novel genes";
        }
    }

    my $final_line = 'Contains';
    if (@DEline == 0) {
        $final_line .= ' no genes.';
    }
    else {
        for (my $i = 0; $i < @DEline; $i++) {
            my $join = ';';
            if ($i == 0) {
                $join = '';
            }
            elsif ($i == $#DEline) {
                $join = '; and';
            }
            $final_line .= "$join $DEline[$i]";
        }
        $final_line .= '.';
    }

    return {
        keywords    => join("\n", @keywords),
        description => $final_line,
    };
}

sub _DE_gene {  ## no critic (Subroutines::ProhibitExcessComplexity)

    my ($self, $gene, $slice_length, $inc_novel, $inc_part_novel) = @_;

    my $gene_name = get_name_Attribute_value($gene);
    $gene_name //= $gene->stable_id;

    my $desc = $gene->description;
    return unless $desc;
    return if     $desc =~ /artefact|artifact/i;

    my $line = '';
    my @keywords;

    # Is all of the gene in the slice?
    if ($gene->start < 1 and $gene->end > $slice_length) {
        $line = 'an internal part of ';
    }
    elsif ($gene->start < 1 and $gene->end <= $slice_length) {
        my $end = $gene->strand == 1 ? q{3'} : q{5'};
        $line = "the $end end of ";
    }
    elsif ($gene->start >= 1 and $gene->end > $slice_length) {
        my $end = $gene->strand == 1 ? q{5'} : q{3'};
        $line = "the $end end of ";
    }

  DESC_SWITCH: {

      # Patterns for clone accession or clone name based gene names
      my $clone_accession = qr{^[A-Z]{1,2}\d{5,6}(\.\d{1,3})?$};
      my $clone_name      = qr{^[A-Z]{1,2}\d{1,3}-?\d{1,3}[A-Z]\d{1,3}(\.\d{1,3})?$};

      if ($desc =~ /novel\s+(protein|transcript|gene)\s+similar/i) {
          $line .= "the gene for " . A($desc);
          last DESC_SWITCH;
      }
      if (($desc =~ /(novel|putative) (protein|transcript|gene)/i)) {
          if ($desc =~ /(zgc:\d+)/) {
              $line .= "a gene for a novel protein ($1)";
          }
          else {
              $line ? &$inc_part_novel : &$inc_novel;
              $line = '';       # don't want to cause anything to be added to DE_line array here
          }
          last DESC_SWITCH;
      }
      if ($desc =~ /pseudogene/i) {
          if (   $gene_name !~ /$clone_accession/
                 && $gene_name !~ /$clone_name/)
          {
              $line .= A($desc) . ' ' . $gene_name;
          }
          else {

              # in a pseudogene named after its clones,
              # locusname is not interesting
              $line .= A($desc);
          }
          last DESC_SWITCH;
      }
      if ($gene_name !~ /\.\d/) {
          $line .= "the $gene_name gene for $desc";
          push @keywords, $gene_name;
          last DESC_SWITCH;
      }
      {
          # DEFAULT
          $line .= "a gene for " . A($desc);
      }
    } # DESC_SWITCH

    return { DE_line => $line, keywords => \@keywords };
}


=head2 write_region

Input: region data, author, locknums.

Output: updated region, or error.

=cut

sub write_region {
    my ($self) = @_;

    my $server = $self->server;

    my ($action, $serialised_output);
    try {
        $action = 'init';
        $server->require_method('POST');
        my $slb = $self->_slice_lock_broker(1);
        # author is checked against the locks by the broker.
        # we don't check source hostname: sessions do sometimes move around.

        $action = 'lock';
        my $current_region;
        $slb->exclusive_work # do lock, write and commit; or rollback
          (sub {
               $action = 'locked';
               $current_region = $self->_write_region_exclusive(\$action, $slb);
           });

        $action = 're-serialise';
        $serialised_output = $self->serialise_region($current_region);

    } catch {
        chomp;
        die "Writing region failed to $action \[$_]";
    };
    return $serialised_output;
}

sub _write_region_exclusive { # runs under $slb->exclusive_work
    my ($self, $action_sref, $slb) = @_;
    my $server = $self->server;

    $$action_sref = 'convert XML to otter';
    my $xml_string = $server->require_argument('data');
    my $new_region = $self->deserialise_region($xml_string);

    $$action_sref = 'compare assemblies'; # compare XML assembly with database assembly
    my $db_region = $self->_fetch_db_region($new_region);
    my $ci_hash   = $self->_compare_region_create_ci_hash($new_region, $db_region);

    $$action_sref = 'locks check';
    $slb->assert_bumped($db_region->slice);

    $$action_sref = 'write';
    my $time_now = do {
        my ($first_lock) = $slb->locks;
        # everything that needs saving should use this timestamp:
        $first_lock->ts_activity;
    };

    my $author_obj = $slb->author;
    my $odba = $self->server->otter_dba();

    # update all contig_info and contig_info_attrib
    while (my ($contig_name, $pair) = each %$ci_hash) {
        my ($db_ctg_slice, $xml_ci_attribs) = @$pair;
        warn "Ignoring contig info-attrib for '$contig_name'\n";
    }

    ## strip_incomplete_genes for the xml genes
    my @new_genes = $new_region->genes;
    $self->_strip_incomplete_genes(\@new_genes);

    my $db_slice = $db_region->slice;

    ##fetch database genes and compare to find the new/modified/deleted genes
    warn "Fetching database genes for comparison...\n";
    my $ga =  $db_slice->adaptor->db->get_GeneAdaptor();
    my $db_genes = $ga->fetch_all_by_Slice($db_slice) || [];
    $self->_strip_incomplete_genes($db_genes);
    warn "Comparing " . scalar(@$db_genes) . " old to " . scalar(@new_genes) . " new gene(s)...\n";

    my $gene_adaptor = $odba->get_GeneAdaptor;
    warn "Attaching gene to slice \n";

    my @changed_genes;
    foreach my $gene (@new_genes) {
        # attach gene and its components to the right slice
        $gene->slice($db_slice);
        # update author in gene and transcript
        $gene->gene_author($author_obj);

        foreach my $tran (@{ $gene->get_all_Transcripts }) {
            $tran->slice($db_slice);
            $tran->transcript_author($author_obj);

            foreach my $exon (@{ $tran->get_all_Exons }) {
                $exon->slice($db_slice);
                $self->fill_exon_align_evidence($exon, $tran);

            }
        }
        foreach my $exon (@{ $gene->get_all_Exons }) {
            $exon->slice($db_slice);
        }
        # update all gene and its components in db (new/mod)
        $gene->is_current(1);

        $slb->assert_bumped($gene->slice);
        if ($gene_adaptor->store($gene, $time_now)) {
            push(@changed_genes, $gene);
        }
    }
    warn "Updated " . scalar(@changed_genes) . " genes\n";

    my %stored_genes_hash = map {$_->stable_id, $_} @new_genes;

    my $del_count = 0;
    foreach my $dbgene (@$db_genes) {
        next if $stored_genes_hash{$dbgene->stable_id};

        ##attach gene and its components to the right slice
        $dbgene->slice($db_slice);
        ##update author in gene and transcript
        $dbgene->gene_author($author_obj);
        foreach my $tran (@{ $dbgene->get_all_Transcripts }) {
            $tran->slice($db_slice);
            $tran->transcript_author($author_obj);
        }
        ##update all gene and its components in db (del)

        # Setting is_current to 0 will cause the store method to delete it.
        $dbgene->is_current(0);
        $slb->assert_bumped($dbgene->slice);
        $gene_adaptor->store($dbgene, $time_now);
        $del_count++;
        warn "Deleted gene " . $dbgene->stable_id . "\n";
    }
    warn "Deleted $del_count Genes\n" if ($del_count);

    my $ab = $odba->get_AnnotationBroker();

    # Because exons are shared between transcripts, genes and gene versions
    # setting which are current is not simple
    #$ab->set_exon_current_flags($db_genes, \@new_genes);

    ##update feature_sets
    ##SimpleFeatures - deletes old features(features not in xml)
    ##and stores the current featues in databse(features in xml)
    my @new_simple_features = $new_region->seq_features;
    my $sfa                 = $odba->get_SimpleFeatureAdaptor;
    my $db_simple_features  = $sfa->fetch_all_by_Slice($db_slice);

    my ($delete_sf, $save_sf) = $ab->compare_feature_sets($db_simple_features, \@new_simple_features);
    foreach my $del_feat (@$delete_sf) {
        $slb->assert_bumped($del_feat->slice);
        $sfa->remove($del_feat);
    }
    warn "Deleted " . scalar(@$delete_sf) . " SimpleFeatures\n";
    foreach my $new_feat (@$save_sf) {
        $new_feat->slice($db_slice);
        $slb->assert_bumped($new_feat->slice);
        $sfa->store($new_feat);
    }
    warn "Saved " . scalar(@$save_sf) . " SimpleFeatures\n";

    ##assembly_tags are not taken into account here, as they are not part of annotation nor versioned ,
    ##but may be required in the future
    ##fetch a new slice, and convert this new_slice to xml so that
    ##the response xml has all the above changes done in this session

    # Pass on to the xml generator the set of changed genes, and
    # all simple features
    my $current_region =  Bio::Vega::Region->new(
            slice         => $db_slice,
            server_action => $self,
            );
    $current_region->genes(@changed_genes);
    $current_region->seq_features(@new_simple_features);
    $current_region->fetch_species;
    $current_region->fetch_CloneSequences;

    return $current_region;
}

sub fill_exon_align_evidence() {
  my ($self, $exon, $transcript) = @_;

  my $pipeline_db = $self->server->dataset->pipeline_dba;


  my $protein_adaptor = $pipeline_db->get_ProteinAlignFeatureAdaptor;
  my $dna_adaptor = $pipeline_db->get_DnaAlignFeatureAdaptor;
  my $transformed_exon = $exon->transform('seqlevel');

  my $start_Exon;
  my $end_Exon;
  my $target_slice = $transcript->slice;

  my $exon_projection_slice = $transformed_exon->slice;
  my $exon_projection_slice_name = $exon_projection_slice->seq_region_name;
  my $target_slice_contig = $target_slice->adaptor->fetch_by_region('seqlevel', $exon_projection_slice_name, $exon_projection_slice->start, $exon_projection_slice->end, $exon_projection_slice->strand);
  if ($transformed_exon) {
#       If we could transfer the exon on the sequence level (contig), we are trying to find the contig in the pipeline database and the target database.
#       Then we can get all supporting evidence which overlap the exon, add them to the exon and transfer them all to the top level
      my $exon_projection_slice = $transformed_exon->slice;
      my $exon_projection_slice_name = $exon_projection_slice->seq_region_name;
#       Loutre contigs have the start and add concatented to the accession: AL671879.2.1.176995
#       but we do not want that.
#       They can also use old data so we need some checks first

        $exon_projection_slice_name =~ s/\.\d+\.\d+$//;
        my $pipeline_slice = $pipeline_db->get_SliceAdaptor->fetch_by_region('seqlevel', $exon_projection_slice->seq_region_name, $exon_projection_slice->start, $exon_projection_slice->end, $exon_projection_slice->strand);
        if ($pipeline_slice) {


          my %supporting_evidences;
          foreach my $evidence (@{$transcript->evidence_list}) {
            my $evidence_name = $evidence->name;
            $evidence_name =~ s/^\w+://;
            my $sfs;
            if ($evidence->type eq 'Protein') {
              $sfs = $protein_adaptor->fetch_all_by_Slice_constraint($pipeline_slice, "hit_name = '$evidence_name'");
            }
            else {
              $sfs = $dna_adaptor->fetch_all_by_Slice_constraint($pipeline_slice, "hit_name = '$evidence_name'");
            }
            my $added_feature = 0;
            foreach my $sf (@$sfs) {
              next if ($sf->analysis->logic_name =~ /_raw$/);
              my $strand = $sf->strand;
              if (defined $sf->hstrand) {
                $strand *= $sf->hstrand;
              }
            if ($sf->slice->seq_region_name eq $exon_projection_slice->seq_region_name and $strand == $transformed_exon->strand and $sf->start <= $transformed_exon->end and $sf->end >= $transformed_exon->start) {
                $supporting_evidences{$sf->hseqname} = $sf;
                $added_feature = 1;
              }
            }
              }
          $transformed_exon->add_supporting_features(values %supporting_evidences);
          my $toplevel_exon = $transformed_exon->transform('toplevel');
          if ($toplevel_exon) {

            $self->check_all_supporting_evidences($toplevel_exon, $target_slice, \%supporting_evidences, $exon, $start_Exon, $end_Exon, $pipeline_slice, $transcript);
          }
          else {
            my $target_contig_projection;
            eval {
              $target_contig_projection = $target_slice_contig->project($target_slice->coord_system->name, $target_slice->coord_system->version);
            };
            if ($target_contig_projection) {
              if (@$target_contig_projection == 1) {
                my $target_contig_proj_toplevel = $target_contig_projection->[0]->to_Slice;
                my $min_start = $transformed_exon->start;
                my $max_end = $transformed_exon->end;
                foreach my $sf (@{$transformed_exon->get_all_supporting_features}) {
                  $min_start = $sf->start if ($sf->start < $min_start);
                  $max_end = $sf->end if ($sf->end > $max_end);
                }
                if (($target_contig_proj_toplevel->strand == 1 and $transformed_exon->start < $target_contig_projection->[0]->from_start)
                    or ($target_contig_proj_toplevel->strand == -1 and $transformed_exon->end > $target_contig_projection->[0]->from_end)) {
                  my $diff = $target_contig_projection->[0]->from_start-$min_start;
                  $transformed_exon->start($diff+$transformed_exon->start);
                  $transformed_exon->end($diff+$transformed_exon->end);
                  foreach my $sf (@{$transformed_exon->get_all_supporting_features}) {
                    $sf->start($diff+$sf->start);
                    $sf->end($diff+$sf->end);
                  }
                  $toplevel_exon = $transformed_exon->transfer($target_slice);
                  if ($toplevel_exon) {
                    $toplevel_exon->start($toplevel_exon->start-abs($diff));
                    $toplevel_exon->end($toplevel_exon->end-abs($diff));
                    foreach my $sf (@{$toplevel_exon->get_all_supporting_features}) {
                      $sf->start($sf->start-abs($diff));
                      $sf->end($sf->end-abs($diff));
                    }
                    $self->check_all_supporting_evidences($toplevel_exon, $target_slice, \%supporting_evidences, $exon, $start_Exon, $end_Exon, $pipeline_slice, $transcript);
                  }
                  else {
                    warn('NOT SURE WHAT TO DO NOW');
                  }
                }
                elsif (($target_contig_proj_toplevel->strand == 1 and $transformed_exon->end > $target_contig_projection->[0]->from_end)
                    or ($target_contig_proj_toplevel->strand == -1 and $transformed_exon->start < $target_contig_projection->[0]->from_start)) {
                  my $diff = $max_end-$target_contig_projection->[0]->from_end;
                  $transformed_exon->start($transformed_exon->start-$diff);
                  $transformed_exon->end($transformed_exon->end-$diff);
                  foreach my $sf (@{$transformed_exon->get_all_supporting_features}) {
                    $sf->start($sf->start-$diff);
                    $sf->end($sf->start-$diff);
                  }
                  $toplevel_exon = $transformed_exon->transfer($target_slice);
                  if ($toplevel_exon) {
                    warn(' TDONE');
                    $toplevel_exon->start($toplevel_exon->start+abs($diff));
                    $toplevel_exon->end($toplevel_exon->end+abs($diff));
                  foreach my $sf (@{$toplevel_exon->get_all_supporting_features}) {
                      $sf->start($sf->start+abs($diff));
                      $sf->end($sf->start+abs($diff));
                    }
                    check_all_supporting_evidences($toplevel_exon, $target_slice, \%supporting_evidences, $exon, $start_Exon, $end_Exon, $pipeline_slice, $transcript);
                  }
                  else {
                    warn('NOT SURE WHAT TO DO NOW');
                  }
                }
                else {
                  return;
                }
              }
              else {
                return;
              }
            }
            else {
              error('COULD NOT PROJECT target_slice_contig TO toplevel');
            }
          }
        }
        else {
          warn('Could not retrieve an exon slice from the pipeline db '.$exon_projection_slice->seq_region_name);
        }
    }
    else {
      my $exon_slice = $exon->slice;
      $exon->slice($target_slice);
      my $slice = $exon_slice->adaptor->fetch_by_region($exon_slice->coord_system->name, $exon_slice->seq_region_name, $exon->seq_region_start, $exon->seq_region_end, $exon_slice->strand, $exon_slice->coord_system->version);
      my $slice_projection = $slice->project('seqlevel');
      if ($slice_projection) {
        my %features;
        foreach my $elm (@$slice_projection) {
          my $exon_projection_slice = $elm->to_Slice;
          my $pipeline_slice = $pipeline_db->get_SliceAdaptor->fetch_by_region('seqlevel', $exon_projection_slice->seq_region_name, $exon_projection_slice->start, $exon_projection_slice->end, $exon_projection_slice->strand);
          if ($pipeline_slice) {
            foreach my $evidence (@{$transcript->evidence_list}) {
              my $evidence_name = $evidence->name;
              $evidence_name =~ s/^\w+://;
              my $sfs;
              if ($evidence->type eq 'Protein') {
                $sfs = $protein_adaptor->fetch_all_by_Slice_constraint($pipeline_slice, "hit_name = '$evidence_name'");
              }
              else {
                $sfs = $dna_adaptor->fetch_all_by_Slice_constraint($pipeline_slice, "hit_name = '$evidence_name'");
              }
              foreach my $sf (@$sfs) {
                next if ($sf->analysis->logic_name =~ /_raw$/);
                my $strand = $sf->strand;
                if (defined $sf->hstrand) {
                  $strand *= $sf->hstrand;
                }
                  $sf->slice($exon_projection_slice);
                my $transformed_sf;
                my $cut_sf;
                if ($sf->start < 1 or $sf->end > $exon_projection_slice->length or $sf->end > $exon_projection_slice->end) {
                  my %tmp_sf = %$sf;
                  $cut_sf = ref($sf)->new_fast(\%tmp_sf);
                  if ($cut_sf->start < 1) {
                    $cut_sf->start(1);
                  }
                  if ($cut_sf->end > $exon_projection_slice->length or $cut_sf->length > $exon_projection_slice->length) {
                    $cut_sf->end($exon_projection_slice->length);
                  }
                  set_hstart_hend($sf, $cut_sf);
                  $sf = $cut_sf;
                }
                my ($target_exon_projection_slice_name) = $exon_projection_slice->seq_region_name =~ /^([^.]+\.\d+)/;
                my $target_exon_projection_slice = $target_slice->adaptor->fetch_by_region($exon_projection_slice->coord_system->name, $target_exon_projection_slice_name, $exon_projection_slice->start, $exon_projection_slice->end);
                if ($target_exon_projection_slice) {
                  $sf->slice($target_exon_projection_slice);
                }
                else {
                  warn('Could not find contig '.$exon_projection_slice->name);
                }
                $transformed_sf = $sf->transfer($target_slice);
                if ($transformed_sf) {
          #                    if ($strand == $exon->strand) {
                    $transformed_sf->slice($target_slice);
                    push(@{$features{$evidence_name}}, $transformed_sf);
#                    }
#                    else {
#                      warn($transformed_sf->hseqname.' '.$transformed_sf->slice->seq_region_name.' '.$transformed_sf->start.' '.$transformed_sf->end.' '.$transformed_sf->strand.' '.$transformed_sf->hstart.' '.$transformed_sf->hend.' '. $transformed_sf->hstrand);
#                    }
                }
                else {
                  warn('Could not project evidence '.$sf->hseqname.' to slice '.$slice->name);
                }
              }
            }
          }
          else {
            warn('Could not retrieve an exon slice from the pipeline db '.$exon_projection_slice->seq_region_name);
          }
        }
        foreach my $feature_name (keys %features) {
          if (@{$features{$feature_name}}) {
            my $new_feature;
            my $hstart = $features{$feature_name}->[0]->hstart;
            my $hend = $features{$feature_name}->[0]->hend;
            foreach my $sf (sort {$a->start <=> $b->start} @{$features{$feature_name}}) {
              if ($new_feature) {
                $hstart = $sf->hstart if ($sf->hstart < $hstart);
                $hend = $sf->hend if ($sf->hend < $hend);
                $new_feature->end($sf->end);
              }
              else {
                $new_feature = $sf;
              }
            }
            $new_feature->hstart($hstart);
            $new_feature->hend($hend);
          $exon->add_supporting_features($new_feature);
            $exon->start($new_feature->start);
            $exon->end($new_feature->end);
          }
          else {
            warn('No match for '.$feature_name.' '.$exon->start.' '.$exon->end.' '.$exon->strand.' '.$exon->slice->name);
          }
        }
      }
      else {
        warn('Could not transform exon '.$exon->stable_id_version.' '.$exon->start.' '.$exon->end.' '.$exon->strand.' '.$exon->slice->name);
      }
      if ($exon->slice->is_toplevel) {
        $transcript->add_Exon($exon);
        if ($start_Exon) {
          $transcript->translation->start_Exon($exon) if ($start_Exon == $exon);
          $transcript->translation->end_Exon($exon) if ($end_Exon == $exon);
        }
      }
      else {
        my $exon_toplevel = $exon->transform('toplevel', $exon->slice->coord_system->version);
        if ($exon_toplevel) {
          $transcript->add_Exon($exon_toplevel);
          if ($start_Exon) {
            $transcript->translation->start_Exon($exon_toplevel) if ($start_Exon == $exon);
            $transcript->translation->end_Exon($exon_toplevel) if ($end_Exon == $exon);
          }
        }
        else {
          warn('Failed to transform exon to toplevel for '.$exon->display_id.' '.$exon->slice->name);
        }
      }
    }
  return;
}

sub add_translation_attributes {
  my ($self, $transcript) = @_;

  my @translation_attributes;
  warn(' GETTING ATTRIBUTES');
  foreach my $attribute (@{$transcript->get_all_Attributes('hidden_remark')}, @{$transcript->get_all_Attributes('remark')}) {
    my $value = $attribute->value;
    if ($value =~ /^selenocystein\w+\s+\d+/) {
      warn(' SELENO '.$value);
      while($value =~ / (\d+)/gc) {
        my $seq_edit = Bio::EnsEMBL::SeqEdit->new(
                                        -CODE    => '_selenocysteine',
                                        -NAME    => 'Selenocysteine',
                                        -DESC    => 'Selenocysteine',
                                        -START   => $1,
                                        -END     => $1,
                                        -ALT_SEQ => 'U'
                                        );
        push(@translation_attributes, $seq_edit->get_Attribute);
      }
    }
  }
  if (scalar(@translation_attributes)) {
    warn(' ADDING '.scalar(@translation_attributes).' ATTRIBUTES');
    $transcript->translation->add_Attributes(@translation_attributes);
  }
}


sub check_all_supporting_evidences {
  my ($self, $toplevel_exon, $target_slice, $supporting_evidences, $exon, $start_Exon, $end_Exon, $pipeline_slice, $transcript) = @_;
# When we have transfered the exon, we need to make sure that it is on the top level sequence
# we aim for and that the slice object is on the forward (1) strand. Otherwise it might cause
# problems later
  if ($toplevel_exon->slice->strand != -1  && $toplevel_exon->slice->name eq $target_slice->name) {
#   If a supporting evidence has not been transfered, there will be an undef value in the array
#   It can happened when the feature is longer than the exon and is overlapping two contigs in
#   the assembly or if there is a small sequence to correct the clone
    my $sfs = $toplevel_exon->get_all_supporting_features;
    foreach my $sf (@$sfs) {
      if ($sf) {
        delete $supporting_evidences->{$sf->hseqname};
      }
    }
    if (keys %$supporting_evidences) {
      $toplevel_exon->flush_supporting_features;
      $toplevel_exon->add_supporting_features(grep {defined $_} @$sfs);
      foreach my $sf (values %$supporting_evidences) {
#       We will try to project the contig to the top level, then for each of the top level region
#       we will resize the feature to make it fit on the region and we will transfer the feature
#       to the top level.
        my $sf_slice = $sf->slice->sub_Slice($sf->start, $sf->end);
        my $sf_on_sf_slice = $sf->transfer($sf_slice);
        my $projected_slice = $sf_on_sf_slice->slice->project($target_slice->coord_system->name, $target_slice->coord_system->version);
        if ($projected_slice) {
          my $region_start = $projected_slice->[0]->from_start;
          my $region_end = $projected_slice->[-1]->from_end;
          my $previous_end = 0;
          my $new_start;
          my $new_end;
          my @slices_to_project;
          my @sf_fragments;
          foreach my $elm (@$projected_slice) {
            next unless ($elm->to_Slice->seq_region_name eq $target_slice->seq_region_name);
            my %tmp_sf = %$sf_on_sf_slice;
            my $cut_sf = ref($sf_on_sf_slice)->new_fast(\%tmp_sf);
            my $exon_sub_slice;
            if ($elm->from_start > 1) {
              if ($region_start == $elm->from_start or $previous_end) {
                $exon_sub_slice = $exon->slice->sub_Slice($previous_end || $elm->to_Slice->start-$elm->from_start, $elm->to_Slice->start-1);
                if (!$exon_sub_slice) {
                  my $tmp_slice = $target_slice->sub_Slice($previous_end || $elm->to_Slice->start-$elm->from_start, $elm->to_Slice->start-1);
                  if ($tmp_slice) {
                    my $tmp_eps = $tmp_slice->project('seqlevel');
                    if ($tmp_eps and @$tmp_eps == 1) {
                      my $tmp_eps_slice = $tmp_eps->[0]->to_Slice;
                      my $tmp_eps_contig = $exon->slice->adaptor->fetch_by_region($tmp_eps_slice->coord_system->name, $tmp_eps_slice->seq_region_name, $tmp_eps_slice->start, $tmp_eps_slice->end, $tmp_eps_slice->strand);
                      if ($tmp_eps_contig) {
                        my $teps_contig_proj = $tmp_eps_contig->project($exon->coord_system->name, $exon->coord_system->version);
                        if ($teps_contig_proj and @$teps_contig_proj == 1) {
                          $exon_sub_slice = $teps_contig_proj->[0]->to_Slice;
                        }
                      }
                    }
                  }
                }
              }
            }
            if ($elm->from_end < $sf_on_sf_slice->end) {
              if ($region_end == $elm->from_end) {
                $exon_sub_slice = $exon->slice->sub_Slice($elm->to_Slice->end+1, $elm->to_Slice->end+$sf_on_sf_slice->end);
              }
            }
            push(@slices_to_project, $exon_sub_slice) if ($exon_sub_slice);
            $cut_sf->start($elm->from_start);
            $cut_sf->end($elm->from_end);
            $previous_end = $elm->to_Slice->end+1;
            set_hstart_hend($sf_on_sf_slice, $cut_sf);
            my $sf_to_add = $cut_sf->transfer($target_slice);
            if ($sf_to_add) {
#             If I could transfer the feature to the target top level, I want to check
#             that the feature I created exists in the pipeline database.
#             So I need to project the top level slice to the sequence level. Then I can
#             fetch the feature on the contig if it exists
      #              info(__LINE__.' '.'SLICES '.$exon->slice->name.' '.$new_start.' '.$new_end);
              push(@sf_fragments, $sf_to_add);
            }
            else {
              warn('WEIRD it was cut to fit');
            }
          }
          foreach my $loutre_side_slice (@slices_to_project) {
            my $loutre_side_projection = $loutre_side_slice->project('seqlevel');
            if ($loutre_side_projection) {
              foreach my $lsp (@$loutre_side_projection) {
                my $loutre_side_contig = $lsp->to_Slice;
                my $short_contig_name = $loutre_side_contig->seq_region_name;
                $short_contig_name =~ s/\.\d+\.\d+$//;
                my $target_side_slice = $target_slice->adaptor->fetch_by_region('seqlevel', $short_contig_name, $loutre_side_contig->start, $loutre_side_contig->end, $loutre_side_contig->strand);
                if ($target_side_slice) {
                  my $pipeline_side_slice = $pipeline_slice->adaptor->fetch_by_region('seqlevel', $loutre_side_contig->seq_region_name, $loutre_side_contig->start, $loutre_side_contig->end, $loutre_side_contig->strand);
                  if ($pipeline_side_slice) {
                    my $side_sfs = $sf_on_sf_slice->adaptor->fetch_all_by_Slice_constraint($pipeline_side_slice, 'hit_name = "'.$sf_on_sf_slice->hseqname.'"', $sf_on_sf_slice->analysis->logic_name);
                    if (@$side_sfs) {
                      foreach my $side_sf (@$side_sfs) {
                        if ($side_sf->start <= $lsp->from_end and $side_sf->end >= $lsp->from_start) {
                          my %sidetmp_sf = %$side_sf;
                          my $sidecut_sf = ref($side_sf)->new_fast(\%sidetmp_sf);
                          if (1 > $sidecut_sf->start) {
                            $sidecut_sf->start(1);
                          }
                          if ($lsp->from_end < $sidecut_sf->end) {
                            $sidecut_sf->end($lsp->from_end);
                          }
                          set_hstart_hend($side_sf, $sidecut_sf);
                          $sidecut_sf->slice($target_side_slice);
                          my $sub_sf = $sidecut_sf->transfer($target_slice);
                          if ($sub_sf) {
                            push(@sf_fragments, $sub_sf);
                          }
                          else {
                            warn('WEIRD: a sub object could not be transfered to the target_slice');
                          }
                        }
                        else {
                          warn('This does not fit here');
                        }
                      }
                    }
                    else {
                      my %sidetmp_sf = %$sf_on_sf_slice;
                      my $sidecut_sf = ref($sf_on_sf_slice)->new_fast(\%sidetmp_sf);
                      $sidecut_sf->hseqname('dummy');
                      $sidecut_sf->slice($target_side_slice);
                      $sidecut_sf->start(1);
                      $sidecut_sf->end($target_side_slice->length);
                      my $sub_sf = $sidecut_sf->transfer($target_slice);
                      if ($sub_sf) {
                        warn(' SUBD SF '.$sub_sf->hseqname.' '.$sub_sf->slice->seq_region_name.' '.$sub_sf->start.' '.$sub_sf->end.' '.$sub_sf->strand.' '.$sub_sf->hstart.' '.$sub_sf->hend.' '.$sub_sf->hstrand.' '.$sub_sf->cigar_string);
                        push(@sf_fragments, $sub_sf);
                      }
                      else {
                        warn('WEIRD: a sub object could not be transfered to the target_slice');
                      }
                    }
                  }
                  else {
                    warn('Could not find '.$loutre_side_contig->name.' in pipeline db');
                  }
                }
                else {
                  warn('Could not find '.$loutre_side_contig->name.' in target_db');
                }
              }
            }
            else {
              warn('Could not find seqlevel for '.$loutre_side_slice->name);
            }
          }
          my $future_start = $sf_fragments[0]->start;
          my $future_end = $sf_fragments[-1]->end;
          my $has_gap = 0;
          my $last_sf_end;
          foreach my $future_sf (sort {$a->start <=> $b->start} @sf_fragments) {
            $future_start = $future_sf->start if ($future_start > $future_sf->start);
            $future_end = $future_sf->end if ($future_end < $future_sf->end);
            if ($last_sf_end) {
              ++$has_gap if ($last_sf_end+1 != $future_sf->start);
            }
            $last_sf_end = $future_sf->end;
          }
          if ($sf_on_sf_slice->length == ($future_end-$future_start+1)) {
            $sf_on_sf_slice->slice($sf_fragments[0]->slice);
            $sf_on_sf_slice->start($future_start);
            $sf_on_sf_slice->end($future_end);
          }
          elsif ($sf_on_sf_slice->length > ($future_end-$future_start+1)) {
            $sf_on_sf_slice->slice($sf_fragments[0]->slice);
            $sf_on_sf_slice->start($future_start);
            $sf_on_sf_slice->end($future_end);
          }
          else {
            $sf_on_sf_slice->slice($sf_fragments[0]->slice);
            $sf_on_sf_slice->start($future_start);
            $sf_on_sf_slice->end($future_end);
          }
          $toplevel_exon->add_supporting_features($sf_on_sf_slice);
        }
        else {
          warn("FAILED PROJECTION");
        }
      }
    }
    if ($toplevel_exon->slice->is_toplevel) {
      $transcript->add_Exon($toplevel_exon);
      if ($start_Exon) {
        $transcript->translation->start_Exon($toplevel_exon) if ($start_Exon == $exon);
        $transcript->translation->end_Exon($toplevel_exon) if ($end_Exon == $exon);
      }
    }
    else {
      my $exon_toplevel = $toplevel_exon->transform('toplevel', $toplevel_exon->slice->coord_system->version);
      if ($exon_toplevel) {
        $transcript->add_Exon($exon_toplevel);
        if ($start_Exon) {
          $transcript->translation->start_Exon($exon_toplevel) if ($start_Exon == $exon);
          $transcript->translation->end_Exon($exon_toplevel) if ($end_Exon == $exon);
        }
      }
      else {
        warn('Failed to transform exon to toplevel for '.$toplevel_exon->display_id.' '.$toplevel_exon->slice->name);
      }
    }
  }
}

sub _slice_lock_broker {
    my ($self, $add_locknums) = @_;
    die unless defined $add_locknums;
    my $server = $self->server;

    my @lockp;
    if ($add_locknums) {
        my $locknums   = $server->require_argument('locknums');
        my @locknum = split ',', $locknums;
        @lockp = (-lockid => \@locknum);
    }

    my $slb = Bio::Vega::SliceLockBroker->new
      (-author => $server->make_Author_obj,
       -adaptor => $server->otter_dba,
       @lockp);

    return $slb;
}

sub _fetch_db_region {
    my ($self, $new_region) = @_;

    my $odba = $self->server->otter_dba;
    my $new_slice = $new_region->slice;

    my $db_slice = $odba->get_SliceAdaptor()->fetch_by_region(
        $new_slice->coord_system->name,
        $new_slice->seq_region_name,
        $new_slice->start,
        $new_slice->end,
        $new_slice->strand,
        $new_slice->coord_system->version,
        );

    my $db_region = Bio::Vega::Region->new;
    $db_region->slice($db_slice);

    my @db_tiles = sort { $a->from_start() <=> $b->from_start() } @{ $db_slice->project('contig') };

    my @db_clone_sequences;
    foreach my $tile ( @db_tiles ) {
        my $ctg_slice = $tile->to_Slice;

        my $cs = Bio::Otter::Lace::CloneSequence->new;
        $cs->chr_start(    $tile->from_start + $new_slice->start - 1 );
        $cs->chr_end(      $tile->from_end   + $new_slice->start - 1 );
        $cs->contig_start( $ctg_slice->start  );
        $cs->contig_end(   $ctg_slice->end    );
        $cs->contig_strand($ctg_slice->strand );

        my $ci = Bio::Vega::ContigInfo->new( -slice => $ctg_slice );
        $cs->ContigInfo($ci);

        push @db_clone_sequences, $cs;
    }
    $db_region->clone_sequences(@db_clone_sequences);

    return $db_region;
}

sub _compare_region_create_ci_hash {
    my ($self, $new_region, $db_region) = @_;

    my $db_slice = $db_region->slice;

    my @new_clone_sequences = $new_region->clone_sequences;
    my @db_clone_sequences  = $db_region->clone_sequences;

    if (@db_clone_sequences != @new_clone_sequences) {
        die "The numbers of tiles in new_region and DB_region do not match";
    }

    my %contig_info_hash;

    for (my $i = 0; $i < @db_clone_sequences; $i++) {

        my $db_asm_start = $db_clone_sequences[$i]->chr_start();
        my $db_asm_end   = $db_clone_sequences[$i]->chr_end();
        my $db_ctg_slice = $db_clone_sequences[$i]->ContigInfo->slice();

        my $new_asm_start  = $new_clone_sequences[$i]->chr_start();
        my $new_asm_end    = $new_clone_sequences[$i]->chr_end();
        my $new_ctg_slice  = $new_clone_sequences[$i]->ContigInfo->slice();
        my $new_ci_attribs = $new_clone_sequences[$i]->ContigInfo->get_all_Attributes();

        if($db_asm_start != $new_asm_start) {
            die "In tile number $i 'asm_start' is different (new_value='$new_asm_start', db_value='$db_asm_start') ";
        }

        if($db_asm_end != $new_asm_end) {
            die "In tile number $i 'asm_end' is different (new_value='$new_asm_end', db_value='$db_asm_end') ";
        }

        foreach my $method (qw{ seq_region_name start end strand }) {
            my $db_value  = $db_ctg_slice->$method();
            my $new_value = $new_ctg_slice->$method();
            if ($db_value ne $new_value) {
                die "In tile number $i '$method' is different (new_value='$new_value', db_value='$db_value') ";
            }
        }

        ## hash the [db_contig, new_ci_attribs] pairs
        # previously, for saving the attributes after the locks are obtained
        # now just warn that they are ignored
        $contig_info_hash{$new_ctg_slice->seq_region_name()} = [ $db_ctg_slice, $new_ci_attribs ];
    }

    return \%contig_info_hash;
}


sub _strip_incomplete_genes {
    my ($self, $gene_list) = @_;

    for (my $i = 0 ; $i < @$gene_list ;) {
        my $gene = $gene_list->[$i];
        if ($gene->truncated_flag) {
            my $gene_name = get_name_Attribute_value($gene);
            warn "Splicing out incomplete gene '$gene_name'\n";
            splice(@$gene_list, $i, 1);
            next;
        } else {
            $i++;
        }
    }
    return;
}


=head2 lock_region

Input: region, author, hostname, client.

Output: error or { locknums => $txt }.

=cut

sub lock_region {
    my ($self) = @_;

    my $server = $self->server;

    my $client = $server->param('client') || $server->cgi->user_agent;
    substr($client, 35) = '...' ## no critic (BuiltinFunctions::ProhibitLvalueSubstr)
      if length($client) > 38; # keep -intent short

    my $cl_host = $server->best_client_hostname;

    my ($lock_token, $action);
    try {
        $action = 'init';
        $server->require_method('POST');
        my $slb = $self->_slice_lock_broker(0);
        $slb->client_hostname($cl_host);

        $action = 'pre-lock';
        $slb->lock_create_for_Slice
          (-slice => $self->slice,
           -intent => "lock_region for $client");

        $action = 'locking';
        $slb->exclusive_work(sub {}); # do lock and commit, or rollback

        $action = 'output';
        my @dbID = map { $_->dbID } $slb->locks;
        $lock_token = { locknums => join ',', @dbID };
    } catch {
        chomp;
        die "Locking slice failed during $action \[$_]";
    };

    return $lock_token;
}


=head2 unlock_region

Input: locknums.

Output: error, or { unlocked => $locknums1, already => $locknums2 }

When the C<locknums> contains multiple locks, they must be compatible
within the SliceLockBroker together i.e. have the same author and
host.

=cut

sub unlock_region {
    my ($self) = @_;
    my $server = $self->server;

    my (%out, $action);
    try {
        $action = 'init';
        $server->require_method('POST');
        my $slb_all = $self->_slice_lock_broker(1);

        $action = 'checking locks';
        my @already = grep { ! $_->is_held } $slb_all->locks;
        my @locked  = grep {   $_->is_held } $slb_all->locks;

        $action = 'to unlock slice';
        if (@locked) {
            my $slb_locked = $self->_slice_lock_broker(0);
            $slb_locked->locks(@locked);
            my $unlock_fail = $slb_locked->exclusive_work(sub {}, 1);
            die $unlock_fail if $unlock_fail;
        }

        $action = 'output';
        $out{unlocked} = join ',', map { $_->dbID } @locked if @locked;
        $out{already} = join ',', map { $_->dbID } @already if @already;
        die "Nothing happened" unless keys %out;

    } catch {
        chomp;
        die "Failed $action \[$_]";
    };

    return \%out;
}

### Null serialisation & deserialisation methods

sub serialise_region {
    my ($self, $region) = @_;
    return $region;
}

sub deserialise_region {
    my ($self, $region) = @_;
    return $region;
}

### Accessors

sub server {
    return shift->{_server};
}

sub slice {
    my ($self, @args) = @_;
    ($self->{_slice}) = @args if @args;
    return $self->{_slice};
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
