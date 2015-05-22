
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

    $transcript->slice($self->slice) unless $transcript->slice;
    foreach my $exon (@{$transcript->get_all_Exons}) {
        $exon->slice($self->slice) unless $exon->slice;
    }

    my $ts_adaptor = $self->_slice_dba->get_TranscriptAdaptor;
    $ts_adaptor->store($transcript);

    $subseq->ensembl_dbID($transcript->dbID);

    $self->logger->debug("Stored transcript for '", $subseq->name, "', dbID: ", $transcript->dbID);
    return;
}

sub update_Transcript {
    my ($self, $new_subseq, $old_subseq, $diffs) = @_;

    my $ts_adaptor = $self->_slice_dba->get_TranscriptAdaptor;
    my $transcript = $ts_adaptor->fetch_by_dbID($old_subseq->ensembl_dbID);

    $self->logger->logconfess("Cannot find transcript for ", $self->_debug_hum_ace($old_subseq)) unless $transcript;

    ## Easiest will be to delete and recreate, a la AceDB

    # $transcript->name      ($new_subseq->name)     if $diffs->{name};
    # $transcript->stable_id ($new_subseq->otter_id) if $diffs->{otter_id};

    # if ($diffs->{list_remarks}) {
    #     $self->_delete_attributes($transcript, 'remark');
    #     $self->_add_attributes(   $transcript, 'remark', $new_subseq->list_remarks);
    # }
    # if ($diffs->{list_annotation_remarks}) {
    #     $self->_delete_attributes($transcript, 'hidden_remark');
    #     $self->_add_attributes(   $transcript, 'hidden_remark', $new_subseq->list_annotation_remarks);
    # }

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

    $self->logger->debug("Created transcript for '", $subseq->name, "'");
    return $transcript;
}

sub _make_exons {
    my ($self, $subseq) = @_;

    my @transcript_exons;
    foreach my $se ($subseq->get_all_Exons) {
        my $te = Bio::Vega::Exon->new(
            -start     => $se->start,
            -end       => $se->end,
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
    $transcript->evidence_list(@evidence_list);
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
    my ($self, $locus) = @_;
    return;
}

sub update_Gene {
    my ($self, $new_locus, $old_locus, $diffs) = @_;
    return;
}

sub slice {
    my ($self, @args) = @_;
    ($self->{'slice'}) = @args if @args;
    my $slice = $self->{'slice'};
    return $slice;
}

sub _slice_dba {
    my ($self) = @_;
    my $_slice_dba = $self->{'_slice_dba'};
    unless ($_slice_dba) {
        $_slice_dba = $self->{'_slice_dba'} = $self->slice->adaptor->db;
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
    my ($ha_obj) = @_;
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

