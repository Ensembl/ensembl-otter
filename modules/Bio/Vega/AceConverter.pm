
### Bio::Vega::AceConverter

package Bio::Vega::AceConverter;

use strict;
use warnings;
use Carp;

use Hum::Ace::AceText;
use Hum::Sort qw{ ace_sort };

use Bio::EnsEMBL::SimpleFeature;
use Bio::EnsEMBL::Analysis;

use Bio::Vega::Gene;
use Bio::Vega::Transcript;
use Bio::Vega::Translation;
use Bio::Vega::Exon;
use Bio::Vega::ContigInfo;
use Bio::Vega::Utils::Attribute qw( add_EnsEMBL_Attributes get_name_Attribute_value add_selenocystein_Attr_from_Remark );

use Bio::Otter::Lace::CloneSequence;

use Bio::Vega::Utils::ExonPhase                   'exon_phase_Ace_to_EnsEMBL';
use Bio::Vega::Utils::GeneTranscriptBiotypeStatus 'method2biotype_status';

my (
    %feature_types,
    %ensembl_slice,
    %otter_slice,
    %ace_database,
    %authors,
    %genes,
    %transcripts,
    %simple_features,
    %analysis,
    %spans,
    %agp_fragments,
    %clone_sequences,
    );

sub DESTROY {
    my ($self) = @_;

    delete(    $feature_types{$self}    );
    delete(    $ensembl_slice{$self}    );
    delete(      $otter_slice{$self}    );
    delete(     $ace_database{$self}    );
    delete(          $authors{$self}    );
    delete(            $genes{$self}    );
    delete(      $transcripts{$self}    );
    delete(  $simple_features{$self}    );
    delete(         $analysis{$self}    );
    delete(            $spans{$self}    );
    delete(    $agp_fragments{$self}    );
    delete(  $clone_sequences{$self}    );

    return;
}

sub new {
    my ($pkg) = @_;

    my $self_str;
    return bless \$self_str, $pkg;
}

sub feature_types {
    my ($self, $feature_types) = @_;

    if ($feature_types) {
        $feature_types{$self} = $feature_types;
    }

    return $feature_types{$self};
}

sub ensembl_slice {
    my ($self) = @_;

    return $ensembl_slice{$self};
}

sub otter_slice {
    my ($self, $otter_slice) = @_;

    if ($otter_slice) {
        $otter_slice{$self} = $otter_slice;
        $ensembl_slice{$self} = $otter_slice->ensembl_slice;
    }
    return $otter_slice{$self};
}

sub genes {
    my ($self) = @_;

    return $genes{$self};
}

sub seq_features {
    my ($self) = @_;

    return $simple_features{$self};
}

sub clone_seq_list {
    my ($self) = @_;

    return $clone_sequences{$self};
}

sub ace_handle {
    my ($self, $ace_handle) = @_;

    if ($ace_handle) {
        $ace_database{$self} = $ace_handle;
    }
    return $ace_database{$self};
}

sub generate_vega_objects {
    my ($self) = @_;

    my $slice_name = $self->otter_slice->name;
    my $ace        = $self->ace_handle;

    # List of people for Authors
    $ace->raw_query(qq{find Person *});
    $self->parse('build_Author', $ace->raw_query('show -a'));

    # Get the Assembly object ...
    my $find_assembly = qq{find Assembly "$slice_name"};
    $ace->raw_query($find_assembly);
    my $ace_txt = $ace->raw_query('show -a');

    # filter by feature type
    my $selected_features = join '|', map { $_->name } @{$self->feature_types};
    $ace_txt =~ s/^Feature\s+"(?!($selected_features)).*\n//mg;

    $self->parse('build_Features_spans_and_agp_fragments', $ace_txt);

    # I think we could switch to a positive filter on Predicted_gene instead
    # of the negative filter on CDS_predicted_by.  (And we could even use
    # a more sensible tag name than "Predicted_gene".)
    $ace->raw_query('query follow SubSequence where ! CDS_predicted_by');
    $self->parse('build_Transcript', $ace->raw_query('show -a'));

    # ... and all the Loci attached to the SubSequences.
    $ace->raw_query('Follow Locus');
    $self->parse('build_Gene', $ace->raw_query('show -a'));
    if (my @tsct_left_over = sort { ace_sort($a, $b) } keys %{$transcripts{$self}}) {
        confess "Unused transcripts after building genes:\n",
            map { sprintf "\t'%s'\n", $_ } @tsct_left_over;
    }

    # Then get the information for the TilePath
    $ace->raw_query($find_assembly);
    $ace->raw_query('Follow AGP_Fragment');
    # Do show -a on a restricted list of tags
    foreach my $tag (qw{
        Otter
        DB_info
        Annotation
        Clone
        DNA
        Length
        })
    {
        $self->parse('build_CloneSequence', $ace->raw_query("show -a $tag"));
    }

    return;
}

sub parse {
    my ($self, $method, $txt) = @_;

    # Strip comments from text
    $txt =~ s{^\s*//.+}{\n}mg;

    # The $method only gets given a single paragraph
    # ie: ace file "object"
    foreach my $obj_txt (grep { /\w/ } split /\n\n+/, $txt) {
        my $ace = Hum::Ace::AceText->new($obj_txt);
        $self->$method($ace);
    }

    return;
}

sub build_Author {
    my ($self, $ace) = @_;

    my (undef, $name) = $ace->class_and_name;
    my $author = Bio::Vega::Author->new(
        -NAME   => $name,
        );
    $authors{$self}{$name} = $author;

    return;
}

sub build_Features_spans_and_agp_fragments {
    my ($self, $ace) = @_;

    my $feat_list = $simple_features{$self} ||= [];
    foreach my $row ($ace->get_values('Feature')) {
        my ($type, $start, $end, $score, $label) = @$row;
        my $strand = 1;
        if ($start > $end) {
            $strand = -1;
            ($start, $end) = ($end, $start);
        }

        # Trim acedb's unnecessary extra precision from score
        # 0.5000 becomes 0.5
        # 1.0000 becomes 1
        $score =~ s/\.?0+$//;

        my $ana = $analysis{$type} ||=
            Bio::EnsEMBL::Analysis->new(-LOGIC_NAME => $type);
        my $sf = Bio::EnsEMBL::SimpleFeature->new(
            -ANALYSIS       => $ana,
            -SLICE          => $self->ensembl_slice,
            -START          => $start,
            -END            => $end,
            -STRAND         => $strand,
            -SCORE          => $score,
            -DISPLAY_LABEL  => $label,
        );
        push(@$feat_list, $sf);
    }

    foreach my $row ($ace->get_values('Subsequence')) {
        my ($tsct_name, $start, $end) = @$row;
        my $strand = 1;
        if ($start > $end) {
            $strand = -1;
            ($start, $end) = ($end, $start);
        }
        $spans{$self}{$tsct_name} = [$start, $end, $strand];
    }

    my $cs_list = $clone_sequences{$self} = [];
    my $chr_offset = $self->ensembl_slice->start - 1;
    my $chr_name = $self->otter_slice->seqname;
    my $ss_name  = $self->otter_slice->ssname;
    foreach my $row ($ace->get_values('AGP_Fragment')) {
        my ($ctg_name, $group_start, $group_end, undef, $start_or_end, $offset, $tile_length) = @$row;

        my ($ctg_strand, $start, $end) =
          $group_start < $group_end
          ? ( 1, $start_or_end, $start_or_end + ($tile_length - 1))
          : (-1, $start_or_end - ($tile_length - 1), $start_or_end);

        my $ctg_start = $offset;
        my $ctg_end   = $offset + $tile_length - 1;

        my $cs = Bio::Otter::Lace::CloneSequence->new;
        $cs->contig_name($ctg_name);
        $cs->contig_start($ctg_start);
        $cs->contig_end($ctg_end);
        $cs->contig_strand($ctg_strand);
        $cs->chromosome($chr_name);
        $cs->chr_start($start + $chr_offset);
        $cs->chr_end($end + $chr_offset);
        $cs->assembly_type($ss_name);
        $cs->ContigInfo(Bio::Vega::ContigInfo->new(-SLICE => $self->ensembl_slice));

        push(@$cs_list, $cs);
    }
    @$cs_list = sort {$a->chr_start <=> $b->chr_start} @$cs_list;

    return;
}

sub build_CloneSequence {
    my ($self, $ace) = @_;

    my (undef, $name) = $ace->class_and_name;

    # The same contig can appear more than once in the assembly
    foreach my $cs (grep { $_->contig_name eq $name } @{$clone_sequences{$self}}) {
        if (my $acc = $ace->get_single_value('Accession')) {
            $cs->accession($acc);
        }
        if (my $sv = $ace->get_single_value('Sequence_version')) {
            $cs->sv($sv);
        }
        if (my $clone_name = $ace->get_single_value('Clone')) {
            $cs->clone_name($clone_name);
        }
        if (my $length = $ace->get_single_value('Length')) {
            $cs->length($length);
        }
        if (my ($dna) = $ace->get_values('DNA')) {
            $cs->length($dna->[1]);
        }

        my $ci = $cs->ContigInfo;
        if (my $desc = $ace->get_single_value('EMBL_dump_info.DE_line')) {
            add_EnsEMBL_Attributes($ci, 'description', $desc);
        }
        foreach my $ann ($ace->get_values('Annotation_remark')) {
            if ($ann->[0] eq 'annotated') {
                add_EnsEMBL_Attributes($ci, 'annotated', 'T');
            } else {
                add_EnsEMBL_Attributes($ci, 'hidden_remark', $ann->[0]);
            }
        }
        if (my $clone = $ace->get_single_value('Clone')) {
            add_EnsEMBL_Attributes($ci, 'intl_clone_name', $clone);
        }
        if (my $acc = $ace->get_single_value('Accession')) {
            add_EnsEMBL_Attributes($ci, 'embl_acc', $acc);
        }
        if (my $sv = $ace->get_single_value('Sequence_version')) {
            add_EnsEMBL_Attributes($ci, 'embl_version', $sv);
        }
        foreach my $kw ($ace->get_values('Keyword')) {
            add_EnsEMBL_Attributes($ci, 'keyword', $kw->[0]);
        }
    }

    return;
}

sub build_Gene {
    my ($self, $ace) = @_;

    my (undef, $name) = $ace->class_and_name;

    my $stable_id   = $ace->get_single_value('Locus_id');
    my $desc        = $ace->get_single_value('Full_name');
    my $source      = $ace->get_single_value('Type_prefix');

    my $tsct_list = $self->gather_transcripts($ace, $name);
    unless (@$tsct_list) {
        confess "No transcripts for gene '$name'";
    }

    my $gene = Bio::Vega::Gene->new(
        -STABLE_ID      => $stable_id,
        -TRANSCRIPTS    => $tsct_list,
        -DESCRIPTION    => $desc,
        -SOURCE         => $source,
        );
    add_EnsEMBL_Attributes($gene, 'name', $name);

    $gene->truncated_flag(1) if $ace->count_tag('Truncated');
    $gene->status('KNOWN')   if $ace->count_tag('Known');

    $gene->set_biotype_status_from_transcripts;

    foreach my $av ($ace->get_values('Alias')) {
        add_EnsEMBL_Attributes($gene, 'synonym', $av->[0]);
    }
    $self->add_remarks($ace, $gene);

    if (my $author_name = $ace->get_single_value('Locus_author')) {
        my $author = $authors{$self}{$author_name}
            or confess "No author object '$author_name'";
        $gene->gene_author($author);
    }

    my $gene_list = $genes{$self} ||= [];
    push(@$gene_list, $gene);

    return;
}

sub gather_transcripts {
    my ($self, $ace, $name) = @_;

    my $tsct_list = [];
    foreach my $tv ($ace->get_values('Positive_sequence')) {
        my ($tsct_name) = $tv->[0];
        my $tsct = delete $transcripts{$self}{$tsct_name}
            or confess "Can't get transcript '$tsct_name' for locus '$name'";
        # warn "Got transcript '$tsct_name' for locus '$name'";
        push (@$tsct_list, $tsct);
    }
    return $tsct_list;
}

sub build_Transcript {
    my ($self, $ace) = @_;

    my (undef, $name) = $ace->class_and_name;

    my $span = $spans{$self}{$name}
        or confess "No start + end for transcript '$name'";

    my $tsct_exons = $self->make_exons($ace, $span);

    my $stable_id   = $ace->get_single_value('Transcript_id');

    my $method_name = $ace->get_single_value('Method');
    $method_name =~ s/^[^:]+://;    # Strip any prefix
    $method_name =~ s/_trunc//;     # Strip _trunc suffix
    my ($biotype, $status) = method2biotype_status($method_name);

    my $tsct = Bio::Vega::Transcript->new(
        -EXONS          => $tsct_exons,
        -STABLE_ID      => $stable_id,
        -BIOTYPE        => $biotype,
        -STATUS         => $status,
        );
    add_EnsEMBL_Attributes($tsct, 'name', $name);

    $self->set_exon_phases_translation_cds_start_end($ace, $tsct);

    # Add supporting evidence to transcript
    $self->add_supporting_evidence($ace, $tsct);

    # Add remarks to transcript
    $self->add_remarks($ace, $tsct);

    if (my $author_name = $ace->get_single_value('Transcript_author')) {
        my $author = $authors{$self}{$author_name}
            or confess "No author object '$author_name'";
        $tsct->transcript_author($author);
    }

    $transcripts{$self}{$name} = $tsct;

    return;
}

sub make_exons {
    my ($self, $ace, $span) = @_;

    my ($tsct_start, $tsct_end, $strand) = @$span;

    my $tsct_exons = [];
    foreach my $row ($ace->get_values('Source_Exons')) {
        my ($ace_start, $ace_end, $stable_id) = @$row;

        my ($start, $end);
        if ($strand == 1) {
            $start = $ace_start + $tsct_start - 1;
            $end   = $ace_end   + $tsct_start - 1;
        }
        else {
            $end   = $tsct_end - $ace_start + 1;
            $start = $tsct_end - $ace_end   + 1;
        }

        my $exon = Bio::Vega::Exon->new(
            -START      => $start,
            -END        => $end,
            -STRAND     => $strand,
            -SLICE      => $self->ensembl_slice,
            -STABLE_ID  => $stable_id,
            );
        push(@$tsct_exons, $exon);
    }
    return $tsct_exons;
}

sub add_remarks {
    my ($self, $ace, $obj) = @_;

    foreach my $value ($ace->get_values('Remark')) {
        add_selenocystein_Attr_from_Remark($obj, $value->[0]);
        add_EnsEMBL_Attributes($obj, 'remark', $value->[0]);
    }
    foreach my $value ($ace->get_values('Annotation_remark')) {
        add_selenocystein_Attr_from_Remark($obj, $value->[0]);
        add_EnsEMBL_Attributes($obj, 'hidden_remark', $value->[0]);
    }

    return;
}

sub add_supporting_evidence {
    my ($self, $ace, $tsct) = @_;

    my $evidence_list = [];
    foreach my $type ( @Bio::Vega::Evidence::Types::ALL ) {
        foreach my $value ($ace->get_values($type . '_match')) {
            my $ev = Bio::Vega::Evidence->new(
                -TYPE   => $type,
                -NAME   => $value->[0],
                );
            push(@$evidence_list, $ev);
        }
    }
    $tsct->evidence_list($evidence_list);

    return;
}

sub set_exon_phases_translation_cds_start_end {
    my ($self, $ace, $tsct) = @_;

    # Fetch the name for use in error messages
    my $name = get_name_Attribute_value($tsct);

    my ($cds) = $ace->get_values('CDS');

    if (! $cds || @$cds == 0) {
        # No translation, so all exons get phase -1
        foreach my $exon (@{ $tsct->get_all_Exons }) {
            $exon->phase(-1);
            $exon->end_phase(-1);
        }
        add_EnsEMBL_Attributes($tsct, 'mRNA_start_NF', 1)
            if $ace->count_tag('Start_not_found');
        add_EnsEMBL_Attributes($tsct, 'mRNA_end_NF', 1)
            if $ace->count_tag('End_not_found');
        return;
    }


    # Set the translation start and end
    my ($cds_start, $cds_end) = @$cds;

    my $translation = Bio::Vega::Translation->new(
        -STABLE_ID      => $ace->get_single_value('Translation_id'),
        );
    $tsct->translation($translation);

    # Set the phase of the exons
    my $start_phase = $ace->get_single_value('Start_not_found');
    if (defined $start_phase) {
        if ($cds_start != 1) {
            confess "Error in transcript '$name'; Start_not_found $start_phase set, but there is 5' UTR\n";
        }
        my $ens_phase = exon_phase_Ace_to_EnsEMBL($start_phase);
        if (defined $ens_phase) {
            $start_phase = $ens_phase;
        } else {
            confess "Error in transcript '$name'; bad value for Start_not_found '$start_phase'\n";
        }
        add_EnsEMBL_Attributes($tsct, 'cds_start_NF', 1);
        add_EnsEMBL_Attributes($tsct, 'mRNA_start_NF', 1);
    }
    elsif ($ace->count_tag('Start_not_found')) {
        add_EnsEMBL_Attributes($tsct, 'mRNA_start_NF', 1);
    }
    $start_phase = 0 unless defined $start_phase;

    my $phase     = -1;
    my $in_cds    = 0;
    my $found_cds = 0;
    my $mrna_pos  = 0;
    my $exon_list = $tsct->get_all_Exons;
    for (my $i = 0 ; $i < @$exon_list ; $i++) {
        my $exon            = $exon_list->[$i];
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
            ### I think this arithmetic is wrong for a single-exon gene:
            $exon_cds_length = $exon_end - $cds_start + 1;
            $translation->start_Exon($exon);
            my $t_start = $cds_start - $exon_start + 1;
            die "Error in '$name' : translation start is '$t_start'"
              if $t_start < 1;
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
            die "Error in '$name' : translation end is '$t_end'"
                if $t_end < 1;
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
    }
    confess("Failed to find CDS in '$name'")
        unless $found_cds;

    if ($ace->count_tag('End_not_found')) {
        add_EnsEMBL_Attributes($tsct, 'mRNA_end_NF', 1);
        if ($exon_list->[-1]->end_phase != -1) {
            # End of last exon is coding
            add_EnsEMBL_Attributes($tsct, 'cds_end_NF', 1);
        }
    }

    return;
}

1;

__END__

=head1 NAME - Bio::Vega::AceConverter

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

