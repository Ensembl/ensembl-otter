
package Bio::Vega::Transform::FromHumAce;

use strict;
use warnings;

use Bio::EnsEMBL::Analysis;

use Bio::Vega::Author;
use Bio::Vega::Evidence;
use Bio::Vega::Exon;
use Bio::Vega::Transcript;
use Bio::Vega::Translation;

use Bio::Vega::Utils::Attribute                   qw( add_EnsEMBL_Attributes );
use Bio::Vega::Utils::ExonPhase                   qw( exon_phase_Ace_to_EnsEMBL );
use Bio::Vega::Utils::GeneTranscriptBiotypeStatus qw( method2biotype_status );

use parent qw{ Bio::Otter::Log::WithContextMixin };

sub new {
    my ($class, %args) = @_;
    my $self = bless { %args }, $class;
    return $self;
}

sub store_Transcript {
    my ($self, $subseq) = @_;

    my $transcript = $self->_transcript_from_SubSeq($subseq);

    my $gene_dbID = $subseq->Locus->ensembl_dbID;
    $gene_dbID or $self->logger->logconfess("SubSeq ",  $self->_debug_hum_ace($subseq),
                                            ": Locus ", $self->_debug_hum_ace($subseq->Locus),
                                            " has no dbID");

    my $ts_adaptor = $self->_slice_dba->get_TranscriptAdaptor;
    $ts_adaptor->store($transcript, $gene_dbID);

    $subseq->ensembl_dbID($transcript->dbID);

    $self->logger->debug("Stored transcript for '", $subseq->name, "', dbID: ", $transcript->dbID);
    return $transcript;
}

sub update_Transcript {
    my ($self, $new_subseq, $old_subseq) = @_;

    my $ts_adaptor = $self->_slice_dba->get_TranscriptAdaptor;

    my $old_ts = $ts_adaptor->fetch_by_dbID($old_subseq->ensembl_dbID);
    $self->logger->logconfess("Cannot find transcript for ", $self->_debug_hum_ace($old_subseq)) unless $old_ts;

    my $new_ts = $self->store_Transcript($new_subseq);
    $ts_adaptor->remove($old_ts);

    $self->logger->debug(sprintf("Updated transcript for '%s', dbID: %d => %d",
                                 $old_subseq->name, $old_subseq->ensembl_dbID, $new_ts->dbID));
    return;
}

sub remove_Transcript {
    my ($self, $subseq) = @_;

    my $ts_adaptor = $self->_slice_dba->get_TranscriptAdaptor;

    my $transcript = $ts_adaptor->fetch_by_dbID($subseq->ensembl_dbID);
    $self->logger->logconfess("Cannot find transcript for ", $self->_debug_hum_ace($subseq)) unless $transcript;

    $ts_adaptor->remove($transcript);
    return;
}

# FIXME: there's a lot of Bio::Vega::AceConverter in here - but that will go soon!

sub _transcript_from_SubSeq {
    my ($self, $subseq) = @_;

    my @exons = $self->_make_exons($subseq);

    my ($biotype, $status) = method2biotype_status($subseq->GeneMethod->name);

    my $transcript = Bio::Vega::Transcript->new(
        -strand    => $subseq->strand,
        -stable_id => $subseq->otter_id,
        -biotype   => $biotype,
        -status    => $status,
        -exons     => \@exons,
        );
    add_EnsEMBL_Attributes($transcript, 'name' => $subseq->name);

    $self->_set_exon_phases_translation_cds_start_end($transcript, $subseq);
    $self->_add_remarks                              ($transcript, $subseq);
    $self->_add_supporting_evidence                  ($transcript, $subseq->evidence_hash);

    $transcript->analysis         ($self->_otter_analysis);
    $transcript->transcript_author($self->_author_object );

    $transcript->slice($self->whole_slice) unless $transcript->slice;
    foreach my $exon (@{$transcript->get_all_Exons}) {
        $exon->slice($self->whole_slice) unless $exon->slice;
    }

    $self->logger->debug(
        sprintf(
            "Created transcript for '%s', [%d-%d:%d]",
            $subseq->name, $transcript->seq_region_start, $transcript->seq_region_end, $transcript->seq_region_strand
        ));
    return $transcript;
}

sub _make_exons {
    my ($self, $subseq) = @_;

    my $offset = $self->session_slice->start - 1;

    my @transcript_exons;
    foreach my $se ($subseq->get_all_Exons) {
        my $te = Bio::Vega::Exon->new(
            -start     => $se->start + $offset,
            -end       => $se->end   + $offset,
            -strand    => $subseq->strand,
            -stable_id => $se->otter_id,
            );
        push @transcript_exons, $te;
    }
    return @transcript_exons;
}

sub _set_exon_phases_translation_cds_start_end {
    my ($self, $transcript, $subseq) = @_;

    my $name = $subseq->name;   # for debugging

    unless ($subseq->translation_region_is_set) {

        foreach my $exon (@{ $transcript->get_all_Exons }) {
            $exon->phase(-1);
            $exon->end_phase(-1);
        }

        if ($subseq->utr_start_not_found) {
            add_EnsEMBL_Attributes($transcript, 'mRNA_start_NF', 1);
        }
        if ($subseq->end_not_found) {
            add_EnsEMBL_Attributes($transcript, 'mRNA_end_NF', 1);
        }

        return;
    }

    my ($transl_start, $transl_end) = $subseq->translation_region;
    my $translation = Bio::Vega::Translation->new(
        -stable_id => $subseq->translation_otter_id,
        );
    $transcript->translation($translation);

    my $start_phase = $subseq->start_not_found;
    my ($cds_start, $cds_end) = $subseq->cds_coords;

    if ($start_phase) {
        if ($cds_start != 1) {
            $self->logger->logconfess(
                sprintf("Error in transcript '%s'; Start_not_found [%s] set, but there is 5' UTR)",
                        $name, $start_phase));
        }
        my $ens_phase = exon_phase_Ace_to_EnsEMBL($start_phase);
        if (defined $ens_phase) {
            $start_phase = $ens_phase;
        } else {
            $self->logger->logconfess("Error in transcript '$name'; bad value for Start_not_found '$start_phase'");
        }
        add_EnsEMBL_Attributes($transcript, 'cds_start_NF', 1);
        add_EnsEMBL_Attributes($transcript, 'mRNA_start_NF', 1);
    }
    elsif ($subseq->utr_start_not_found) {
        add_EnsEMBL_Attributes($transcript, 'mRNA_start_NF', 1);
    }
    $start_phase = 0 unless defined $start_phase;

    my $phase     = -1;
    my $in_cds    = 0;
    my $found_cds = 0;
    my $mrna_pos  = 0;
    my $last_exon;

    foreach my $exon (@{ $transcript->get_all_Exons }) {

        my $strand          = $exon->strand;
        my $exon_start      = $mrna_pos + 1;
        my $exon_end        = $mrna_pos + $exon->length;
        my $exon_cds_length = 0;
        if ($in_cds) {
            $exon_cds_length = $exon->length;
            $exon->phase($phase);
        }
        elsif (!$found_cds && $cds_start <= $exon_end) {
            $in_cds    = 1;
            $found_cds = 1;
            $phase     = $start_phase;

            if ($cds_start > $exon_start) {

                # beginning of exon is non-coding
                $exon->phase(-1);
            }
            else {
                $exon->phase($phase);
            }
            # Comment from Bio::vega::AceConverter, jgrg in 2009, commit id d6468e1f:
            ### I think this arithmetic is wrong for a single-exon gene:
            $exon_cds_length = $exon_end - $cds_start + 1;
            $translation->start_Exon($exon);
            my $t_start = $cds_start - $exon_start + 1;
            $self->logger->logconfess("Error in '$name' : translation start is '$t_start'") if $t_start < 1;
            $translation->start($t_start);
        }
        else {
            $exon->phase($phase);
        }

        my $end_phase = -1;
        if ($in_cds) {
            $end_phase = ($exon_cds_length + $phase) % 3;
        }

        if ($in_cds and $cds_end <= $exon_end) {

            # Last translating exon
            $in_cds = 0;
            $translation->end_Exon($exon);
            my $t_end = $cds_end - $exon_start + 1;
            $self->logger->logconfess("Error in '$name' : translation end is '$t_end'") if $t_end < 1;
            $translation->end($t_end);
            if ($cds_end < $exon_end) {
                $exon->end_phase(-1);
            }
            else {
                $exon->end_phase($end_phase);
            }
            $phase = -1;
        }
        else {
            $exon->end_phase($end_phase);
            $phase = $end_phase;
        }

        $mrna_pos = $exon_end;
        $last_exon = $exon;
    }
    $self->logger->logconfess("Failed to find CDS in '$name'") unless $found_cds;

    if ($subseq->end_not_found) {
        add_EnsEMBL_Attributes($transcript, 'mRNA_end_NF', 1);
        if ($last_exon->end_phase != -1) {
            # End of last exon is coding
            add_EnsEMBL_Attributes($transcript, 'cds_end_NF', 1);
        }
    }

    return;
}

sub _add_remarks {
    my ($self, $transcript, $subseq) = @_;

    my @remarks            = map { ('remark'        => $_) } $subseq->list_remarks;
    my @annotation_remarks = map { ('hidden_remark' => $_) } $subseq->list_annotation_remarks;
    add_EnsEMBL_Attributes($transcript, @remarks, @annotation_remarks);

    return;
}

sub _add_supporting_evidence {
    my ($self, $transcript, $evidence_hash) = @_;
    my @evidence_list;
    foreach my $type (keys %$evidence_hash) {
        foreach my $name ( @{$evidence_hash->{$type}} ) {
            my $evidence = Bio::Vega::Evidence->new(
                -TYPE => $type,
                -NAME => $name,
                );
            push @evidence_list, $evidence;
        }
    }
    $transcript->evidence_list(\@evidence_list);
    return;
}

sub _otter_analysis {
    my ($self) = @_;
    my $_otter_analysis = $self->{'_otter_analysis'};
    unless ($_otter_analysis) {
        $_otter_analysis = $self->{'_otter_analysis'} = Bio::EnsEMBL::Analysis->new( -LOGIC_NAME => 'Otter' );
    }
    return $_otter_analysis;
}

sub store_Gene {
    my ($self, $locus, $subseq) = @_;

    # Make a throw-away transcript from the subseq - should cache?
    my $ts = $self->_transcript_from_SubSeq($subseq);

    my $gene = $self->_gene_from_Locus($locus, [ $ts ]);

    # Throw it away
    my $transcripts = $gene->get_all_Transcripts;
    @$transcripts = ();

    $gene->slice($self->whole_slice) unless $gene->slice;

    my $gene_adaptor = $self->_slice_dba->get_GeneAdaptor;
    $gene_adaptor->store_only($gene);

    $locus->ensembl_dbID($gene->dbID);

    $self->logger->debug("Stored gene for '", $locus->name, "', dbID: ", $gene->dbID);
    return;
}

sub update_Gene {
    my ($self, $new_locus, $old_locus) = @_;

    my $gene_adaptor = $self->_slice_dba->get_GeneAdaptor;
    my $old_gene = $gene_adaptor->fetch_by_dbID($old_locus->ensembl_dbID);

    $self->logger->logconfess("Cannot find gene for ", $self->_debug_hum_ace($old_locus)) unless $old_gene;

    my $old_transcripts = $old_gene->get_all_Transcripts;
    my $transcripts_copy = [ @$old_transcripts ];

    my $new_gene = $self->_gene_from_Locus($new_locus, $old_transcripts); # transcripts for setting coords

    # $old_transcripts is the arrayref associated with $old_gene and now @new_gene, so we empty it to prevent
    # the gene adaptor from storing or removing the transcripts.
    @$old_transcripts = ();

    $new_gene->slice($self->whole_slice) unless $new_gene->slice;
    $gene_adaptor->store_only($new_gene);
    my $new_gene_dbID = $new_gene->dbID;

    # Point existing transcripts at the new version
    my $ts_adaptor = $self->_slice_dba->get_TranscriptAdaptor;
    my $sth = $ts_adaptor->prepare("UPDATE transcript SET gene_id = ? WHERE transcript_id = ?");
    foreach my $ts ( @$transcripts_copy ) {
        $sth->execute($new_gene_dbID, $ts->dbID);
    }
    $sth->finish;

    $gene_adaptor->remove($old_gene);

    $new_locus->ensembl_dbID($new_gene_dbID);

    $self->logger->debug(sprintf("Updated gene for '%s', dbID: %d => %d",
                                 $old_locus->name, $old_locus->ensembl_dbID, $new_gene_dbID));
    return;
}

sub _gene_from_Locus {
    my ($self, $locus, $transcripts) = @_;

    my $gene = Bio::Vega::Gene->new(
        -transcripts => $transcripts,
        -stable_id   => $locus->otter_id,
        -description => $locus->description,
        -source      => $locus->gene_type_prefix,
        );
    add_EnsEMBL_Attributes($gene, 'name' => $locus->name);

    $gene->truncated_flag(1) if $locus->is_truncated;
    $gene->status('KNOWN')   if $locus->known;

    $self->_add_remarks($gene, $locus);

    $gene->analysis   ($self->_otter_analysis);
    $gene->gene_author($self->_author_object );

    $self->logger->debug(
        sprintf("Created gene for '%s', [%d-%d:%d]",
                $locus->name, $gene->seq_region_start, $gene->seq_region_end, $gene->seq_region_strand)
        );
    return $gene;
}

sub session_slice {
    my ($self, @args) = @_;
    ($self->{'session_slice'}) = @args if @args;
    my $session_slice = $self->{'session_slice'};
    return $session_slice;
}

sub whole_slice {
    my ($self, @args) = @_;
    ($self->{'whole_slice'}) = @args if @args;
    my $whole_slice = $self->{'whole_slice'};
    return $whole_slice;
}

sub _slice_dba {
    my ($self) = @_;
    my $_slice_dba = $self->{'_slice_dba'};
    unless ($_slice_dba) {
        $_slice_dba = $self->{'_slice_dba'} = $self->whole_slice->adaptor->db;
    }
    return $_slice_dba;
}

sub author {
    my ($self, @args) = @_;
    ($self->{'author'}) = @args if @args;
    my $author = $self->{'author'};
    return $author;
}

sub _author_object {
    my ($self) = @_;
    my $_author_object = $self->{'_author_object'};
    unless ($_author_object) {
        $_author_object = $self->{'_author_object'} = Bio::Vega::Author->new( -NAME => $self->author );
    }
    return $_author_object;
}

sub _debug_hum_ace {
    my ($self, $ha_obj) = @_;
    return sprintf("'%s' [%s]",
                   $ha_obj->name         // '<unnamed>',
                   $ha_obj->ensembl_dbID // '-'          );
}

sub default_log_context {
    my ($self) = @_;
    return '-FromHumAce-context-not-set-';
}

1;

__END__

=head1 NAME - Bio::Vega::Transform::FromHumAce

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

