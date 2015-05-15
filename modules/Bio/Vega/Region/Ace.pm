
### Bio::Vega::Region::Ace

package Bio::Vega::Region::Ace;

use strict;
use warnings;
use Carp;

use Hum::Ace::AceText;
use Hum::Ace::Assembly;
use Hum::Ace::Clone;
use Hum::Ace::Exon;
use Hum::Ace::Locus;
use Hum::Ace::SubSeq;
use Hum::Ace::SeqFeature::Simple;

use Bio::Vega::Utils::GeneTranscriptBiotypeStatus 'biotype_status2method';

my %ens2ace_phase = (
    0   => 1,
    2   => 2,
    1   => 3,
    );


sub new {
    my ($class, %args) = @_;
    my $self = bless {}, $class;
    return $self;
}


### Where should we add "-D" commands to the ace data?

sub make_ace_string {
    my ($self, $region) = @_;

    # New top level object to generate whole chromosome coordinates
    my $ace_str = $self->make_ace_chr_assembly($region);

    # Assembly object from chromosome slice
    $ace_str .= $self->make_ace_assembly($region);

    # Objects for each genomic clone
    $ace_str .= $self->make_ace_contigs($region);

    # Genes and transcripts
    $ace_str .= $self->make_ace_genes_transcripts($region);

    # Authors - we only store the author name

    # Genomic features
    $ace_str .= $self->make_ace_genomic_features($region);

    return $ace_str;
}

sub make_ace_genes_transcripts {
    my ($self, $region) = @_;

    my $slice_ace   = $self->new_slice_ace_object($region);
    my $slice_name  = $self->make_assembly_name($region);
    my $tsct_str = '';
    my $gene_str = '';

    foreach my $gene ( $region->genes ) {
        my $gene_name = get_first_attrib_value($gene, 'name');
        my $gene_ace = Hum::Ace::AceText->new_from_class_and_name_with_delete('Locus', $gene_name);
        fill_locus_AceText($gene, $gene_ace);

        my $prefix = $gene->source eq 'havana'
            ? ''
            : $gene->source . ':';

        my $trunc_suffix = $gene->truncated_flag ? '_trunc' : '';

        foreach my $tsct (@{$gene->get_all_Transcripts}) {
            my $name = get_first_attrib_value($tsct, 'name') || $tsct->stable_id;
            confess "No name for transcript ", $tsct->dbID unless $name;
            $gene_ace->add_tag('Positive_sequence', $name);
            my @start_end = ($tsct->start, $tsct->end);
            if ($tsct->strand == -1) {
                @start_end = reverse @start_end;
            }
            $slice_ace->add_tag('SubSequence', $name, @start_end);

            my $tsct_ace = Hum::Ace::AceText->new_from_class_and_name_with_delete('Sequence', $name);
            $tsct_ace->add_tag('Source', $slice_name);
            $tsct_ace->add_tag('Locus', $gene_name);
            my $method = $prefix . biotype_status2method($tsct->biotype, $tsct->status) . $trunc_suffix;

            $tsct_ace->add_tag('Method', $method);

            fill_transcript_AceText($tsct, $tsct_ace);

            $tsct_str .= $tsct_ace->ace_string;
        }

        $gene_str .= $gene_ace->ace_string;
    }

    return join("\n", $slice_ace->ace_string, $tsct_str, $gene_str);
}

sub add_attributes_to_Ace {
    my ($obj, $attrib_code, $ace, $ace_key) = @_;

    foreach my $attrib (@{$obj->get_all_Attributes($attrib_code)}) {
        $ace->add_tag($ace_key, $attrib->value);
    }

    return;
}

sub get_first_attrib_value {
    my ($obj, $attrib_code) = @_;

    if (my ($attrib) = @{$obj->get_all_Attributes($attrib_code)}) {
        return $attrib->value;
    } else {
        return;
    }
}

sub fill_transcript_AceText {
    my ($tsct, $ace) = @_;

    if (my $stable = $tsct->stable_id) {
        $ace->add_tag('Transcript_id', $stable);
    }

    if (my $author = $tsct->transcript_author) {
        $ace->add_tag('Transcript_author', $author->name);
    }

    add_attributes_to_Ace($tsct, 'remark',        $ace, 'Remark');
    add_attributes_to_Ace($tsct, 'hidden_remark', $ace, 'Annotation_remark');

    # Translation start and end
    if (my $translation = $tsct->translation) {
        $ace->add_tag('Translation_id', $translation->stable_id);
        if ($tsct->strand == 1) {
            $ace->add_tag('CDS',
                mRNA_posn($tsct, $tsct->coding_region_start),
                mRNA_posn($tsct, $tsct->coding_region_end),
                );
        } else {
            $ace->add_tag('CDS',
                mRNA_posn($tsct, $tsct->coding_region_end),
                mRNA_posn($tsct, $tsct->coding_region_start),
                );
        }
    }
    elsif ($tsct->biotype =~ /pseudo/i) {
        $ace->add_tag('CDS');
        $ace->add_tag('Pseudogene');
    }

    # Exon locations and stable IDs
    my $exons = $tsct->get_all_Exons;
    if ($tsct->strand == 1) {
        my $tsct_offset = $tsct->start - 1;
        foreach my $exon (@$exons) {
            $ace->add_tag(
                'Source_Exons',
                $exon->start - $tsct_offset,
                $exon->end   - $tsct_offset,
                $exon->stable_id,
                );
        }
    } else {
        my $tsct_offset = $tsct->end + 1;
        foreach my $exon (@$exons) {
            $ace->add_tag(
                'Source_Exons',
                $tsct_offset - $exon->end,
                $tsct_offset - $exon->start,
                $exon->stable_id,
                );
        }
    }

    # mRNA and CDS start not found tags
    if (get_first_attrib_value($tsct, 'cds_start_NF')) {
        my $tsl = $tsct->translation
            or confess sprintf("Transcript '%s' has 'CDS start not found' set, but does not have a Translation",
                get_first_attrib_value($tsct, 'name'));
        my $first_exon_phase = $tsl->start_Exon->phase;
        # Used to only issue a warning and set Start_not_found with no value
        # if the first exon phase is not 0, 1 or 2
        my $ace_phase = $ens2ace_phase{$first_exon_phase}
            or confess "No Ace phase for Ensembl exon phase '$first_exon_phase'";
        $ace->add_tag('Start_not_found', $ace_phase);
    }
    elsif (get_first_attrib_value($tsct, 'mRNA_start_NF')) {
        $ace->add_tag('Start_not_found');
    }

    # mRNA and CDS end not found tags
    if (get_first_attrib_value($tsct, 'cds_end_NF') or
        get_first_attrib_value($tsct, 'mRNA_end_NF'))
    {
        $ace->add_tag('End_not_found');
    }

    # Transcript supporting evidence
    foreach my $ev (@{$tsct->evidence_list}) {
        $ace->add_tag($ev->type . '_match', $ev->name);
    }

    return;
}

sub fill_locus_AceText {
    my ($gene, $ace) = @_;

    if (my $stable = $gene->stable_id) {
        $ace->add_tag('Locus_id', $stable);
    }
    if (my $author = $gene->gene_author) {
        $ace->add_tag('Locus_author', $author->email);
    }
    if (my $desc = $gene->description) {
        $ace->add_tag('Full_name', $desc);
    }

    $ace->add_tag('Known')     if $gene->is_known;
    $ace->add_tag('Truncated') if $gene->truncated_flag;

    add_attributes_to_Ace($gene, 'synonym', $ace, 'Alias');
    add_attributes_to_Ace($gene, 'remark',        $ace, 'Remark');
    add_attributes_to_Ace($gene, 'hidden_remark', $ace, 'Annotation_remark');

    my $source = $gene->source;
    if ($source ne 'havana') {
        $ace->add_tag('Type_prefix', $source);
    }

    return;
}

sub new_slice_ace_object {
    my ($self, $region) = @_;

    my $slice_name = $self->make_assembly_name($region);
    return Hum::Ace::AceText->new_from_class_and_name('Sequence', $slice_name);
}

sub make_assembly_name {
    my ($self, $region) = @_;

    my $chr_slice = $region->slice;
    return sprintf "%s_%d-%d",
        $chr_slice->seq_region_name,
        $chr_slice->start,
        $chr_slice->end;
}

sub make_ace_chr_assembly {
    my ($self, $region) = @_;

    my $chr_slice = $region->slice;

    my $ace = Hum::Ace::AceText->new_from_class_and_name('Sequence', $chr_slice->seq_region_name);
    $ace->add_tag('AGP_Fragment',
        $self->make_assembly_name($region), $chr_slice->start, $chr_slice->end,
        'Align', $chr_slice->start, 1, $chr_slice->length,
        );

    return $$ace;
}

sub make_ace_assembly {
    my ($self, $region) = @_;

    my $dataset_name = $region->species or die "species tag is missing";

    my $ace = $self->new_slice_ace_object($region);
    $ace->add_tag('Assembly');
    $ace->add_tag('Species', $dataset_name);

    $ace->add_tag('Assembly_name', $region->slice->seq_region_name);

    # Clone sequences are returned sorted in ascending order by their starts
    my @asm_clone_sequences = $region->sorted_clone_sequences;

    # For contigs which contribute more than once to the assembly
    # we need to record their spans for the Smap tags.
    my %ctg_spans;
    foreach my $acs (@asm_clone_sequences) {
        my $chr_start = $acs->chr_start();
        my $chr_end   = $acs->chr_end();
        my $ctg_slice = $acs->ContigInfo->slice();
        my $name = $ctg_slice->seq_region_name;
        if (my $span = $ctg_spans{$name}) {
            # Extend the span
            $span->[1] = $chr_end;
        } else {
            # Make a new span
            $ctg_spans{$name} = [$chr_start, $chr_end];
        }
    }

    # Create the Smap tags used by acedb to assemble the genomic region
    # from the contigs.
    my $chr_offset = $asm_clone_sequences[0]->chr_start() - 1;
    foreach my $acs (@asm_clone_sequences) {
        my $chr_start   = $acs->chr_start();
        my $chr_end     = $acs->chr_end();
        my $ctg_slice   = $acs->ContigInfo->slice();
        my $attrib_list = $acs->ContigInfo->get_all_Attributes();
        my $name = $ctg_slice->seq_region_name;
        my ($span_start, $span_end) = @{$ctg_spans{$name}};
        if ($ctg_slice->strand == 1) {
            $ace->add_tag('AGP_Fragment', $name,
                $span_start - $chr_offset,
                $span_end   - $chr_offset,
                'Align',
                $chr_start - $chr_offset,
                $ctg_slice->start,
                $ctg_slice->length,
                );
        } else {
            $ace->add_tag('AGP_Fragment', $name,
                $span_end   - $chr_offset,
                $span_start - $chr_offset,
                'Align',
                $chr_end - $chr_offset,
                $ctg_slice->start,
                $ctg_slice->length,
                );
        }
    }

    return $ace->ace_string;
}

sub make_ace_contigs {
    my ($self, $region) = @_;

    my $str = '';
    foreach my $cs ($region->sorted_clone_sequences) {
        $str .= $self->make_ace_ctg($cs);
    }
    return $str;
}

sub make_ace_ctg {
    my ($self, $clone_sequence) = @_;

    my $chr_start   = $clone_sequence->chr_start();
    my $chr_end     = $clone_sequence->chr_end();
    my $ctg_slice   = $clone_sequence->ContigInfo->slice();

    ### Authors don't get parsed from the XML

    my $ace = Hum::Ace::AceText->new_from_class_and_name('Sequence', $ctg_slice->seq_region_name);

    $self->_process_contig_attribs($clone_sequence,
                                   'ace',
                                   sub {
                                       my ($decoder, $value) = @_;
                                       my $tag = $decoder->{'tag'};
                                       my @tags = ref $tag ? @$tag : ( $tag ); # allow multiple tags as arrayref
                                       $ace->add_tag(@tags, $value);
                                   });

    return $ace->ace_string;
}

# 'ace' specs are used in make_ace_ctg()
# 'hum' specs are used in _add_contigs()

my %remark_handlers = (
    'ace' => { tag    => 'Annotation_remark' },
    'hum' => { method => 'add_remark'        },
    );

my %contig_attrib_decoder = (

    'description'     => { 'ace' => { tag    => [ qw( EMBL_dump_info DE_line ) ] },
                           'hum' => { method => 'description' },
    },
    'annotated'       => { 'cnd' => sub { my ($value) = @_; return $value eq 'T'; },
                           'ace' => { tag    => 'Annotation_remark', value => 'annotated' },
                           'hum' => { method => 'add_remark',        value => 'annotated' },
    },
    'hidden_remark'   => \%remark_handlers,
    'remark'          => \%remark_handlers,

    'intl_clone_name' => { 'ace' => { tag    => 'Clone'      },
                           'hum' => { method => 'clone_name' },
    },
    'embl_acc'        => { 'ace' => { tag    => 'Accession' },
                           'hum' => { method => 'accession' },
    },
    'embl_version'    => { 'ace' => { tag    => 'Sequence_version' },
                           'hum' => { method => 'sequence_version' },
    },
    ### Keywords should be turned off once they are
    ### automatically added to EMBL dumps from otter.
    'keyword'         => { 'ace' => { tag    => 'Keyword'     },
                           'hum' => { method => 'add_keyword' },
    },
    );

sub _process_contig_attribs {
    my ($self, $clone_sequence, $type, $applicator) = @_;

    my $attrib_list = $clone_sequence->ContigInfo->get_all_Attributes();
    foreach my $at (@$attrib_list) {
        my ($code, $value) = ($at->code, $at->value);

        my $decoder = $contig_attrib_decoder{$code};
        unless ($decoder) {
            warn "Don't know how to handle contig attrib '$code'\n";
            next;
        };

        my $condition_sub = $decoder->{'cnd'};
        if ($condition_sub) {
            next unless $condition_sub->($value);
        }

        my $value_override = $decoder->{$type}->{'value'};
        if ($value_override) {
            $value = $value_override;
        }
        $applicator->($decoder->{$type}, $value);
    }
    return;
}

sub mRNA_posn {
    my ($tsct, $genomic) = @_;

    my $start   = $tsct->start;
    my $end     = $tsct->end;
    my $strand  = $tsct->strand;

    return if $genomic < $start;
    return if $genomic > $end;

    my $mrna = 1;

    foreach my $exon (@{ $tsct->get_all_Exons }) {
        # Is the genomic location within this exon?
        if ($genomic <= $exon->end and $genomic >= $exon->start) {
            if ($strand == 1) {
                return $mrna + ($genomic - $exon->start);
            } else {
                return $mrna + ($exon->end - $genomic);
            }
        } else {
            $mrna += $exon->length;
        }
    }
    return;
}

sub make_ace_genomic_features {
    my ($self, $region) = @_;

    my @feat_list = $region->seq_features;
    unless (@feat_list) {
        return '';
    }
    my $ace = $self->new_slice_ace_object($region);
    foreach my $feat (@feat_list) {
        # Ace format encodes strand by order of start + end
        my $start = $feat->start;
        my $end   = $feat->end;
        if ($feat->strand == -1) {
            ($start, $end) = ($end, $start);
        }

        my $score = $feat->score;
        $score = 1 unless defined $score;

        my $type;
        if (my $ana = $feat->analysis) {
            $type = $ana->logic_name
                or confess "No logic name attached to Analysis object of Feature";
        } else {
            confess "No Analysis object attached to Feature";
        }

        if (my $label = $feat->display_label) {
            $ace->add_tag('Feature', $type, $start, $end, $score, $label);
        } else {
            $ace->add_tag('Feature', $type, $start, $end, $score);
        }
    }

    return $ace->ace_string;
}


# ---------- build a Hum::Ace::Assembly from region, a la express_data_fetch ----------

sub make_assembly {
    my ($self, $region, $attrs) = @_;

    my $assembly = $self->_make_assembly($region, $attrs);
    $self->_add_simple_features($assembly, $region->seq_features);
    $self->_add_contigs(        $assembly, $region->sorted_clone_sequences);
    $self->_add_genes(          $assembly, $region->genes);
    return $assembly;
}

sub _make_assembly {
    my ($self, $region, $attrs) = @_;

    my $chr_slice = $region->slice;

    my $assembly = Hum::Ace::Assembly->new;
    if ($attrs) {
        foreach my $key ( keys %$attrs ) {
            $assembly->$key($attrs->{$key});
        }
    }
    $assembly->species($region->species);
    $assembly->name(         $self->make_assembly_name($region));
    $assembly->assembly_name($chr_slice->seq_region_name);

    $assembly->Sequence($self->_dna($region, $assembly->name));

    return $assembly;
}

sub _add_simple_features {
    my ($self, $assembly, @seq_features) = @_;

    # FIXME: dup with Hum::Ace::Assembly
    my $coll = $assembly->MethodCollection
      or confess "No MethodCollection attached";

    # We are only interested in the "editable" features on the Assembly.
    my %mutable_method =
      map { lc $_->name, $_ } $coll->get_all_mutable_non_transcript_Methods;

    my @simple_features;
    foreach my $feat (@seq_features) {

        my $type = $feat->analysis->logic_name;
        my $method = $mutable_method{lc $type}
          or next;

        my $ha_feat = Hum::Ace::SeqFeature::Simple->new;
        $ha_feat->seq_Sequence($assembly->Sequence);
        $ha_feat->seq_name(    $type);
        $ha_feat->Method(      $method);
        $ha_feat->seq_start(   $feat->start);
        $ha_feat->seq_end(     $feat->end);
        $ha_feat->seq_strand(  $feat->strand);
        $ha_feat->score(       $feat->score // 1);
        $ha_feat->text(        $feat->display_label);
        $ha_feat->ensembl_dbID($feat->dbID);

        push @simple_features, $ha_feat;
    }
    $assembly->set_SimpleFeature_list(@simple_features);

    return $assembly;
}

sub _dna {
    my ($self, $region, $name) = @_;

    my $dna = $region->slice->seq;

    my $seq = Hum::Sequence::DNA->new;
    $seq->name($name);
    $seq->sequence_string($dna);

    warn "Sequence '$name' is ", $seq->sequence_length, " long\n"; # FIXME: logger
    return $seq;
}

sub _add_contigs {
    my ($self, $assembly, @clone_sequences) = @_;

    # Duplication with Hum::Ace::Assembly->express_data_fetch()
    my %name_clone;
    my $chr_offset = $clone_sequences[0]->chr_start - 1;
    foreach my $cs (@clone_sequences) {
        my $start      = $cs->chr_start - $chr_offset;
        my $end        = $cs->chr_end   - $chr_offset;
        my $ctg_slice  = $cs->ContigInfo->slice;
        my $clone_name = $ctg_slice->seq_region_name;
        my $strand     = $ctg_slice->strand;

        if (my $clone = $name_clone{$clone_name}) {
            if ($clone->assembly_strand != $strand) {
                $clone->assembly_strand(0);
            }
            if ($start < $clone->assembly_start) {
                $clone->assembly_start($start);
            }
            if ($end > $clone->assembly_end) {
                $clone->assembly_end($end);
            }
        } else {
            $clone = Hum::Ace::Clone->new;

            $clone->name(            $clone_name);
            $clone->sequence_length( $cs->length);
            warn "Clone sequence '$clone_name' is '", $cs->length, "' bp long\n";

            $clone->assembly_start( $start);
            $clone->assembly_end(   $end);
            $clone->assembly_strand($strand);

            $self->_process_contig_attribs($cs,
                                           'hum',
                                           sub {
                                               my ($decoder, $value) = @_;
                                               my $method = $decoder->{'method'};
                                               $clone->$method($value);
                                           });

            # Not sure whether we need this, but it allows for deep testing
            $clone->golden_start(1);
            $clone->golden_end($clone->sequence_length);

            $assembly->add_Clone($clone);

            $name_clone{$clone_name} = $clone;
        }
    }
    return $assembly;
}

sub _add_genes {
    my ($self, $assembly, @genes) = @_;

    # DUP Hum::Ace::Assembly->express_data_fetch
    my %name_method = map {$_->name, $_} $assembly->MethodCollection->get_all_transcript_Methods;

    foreach my $gene (@genes) {

        my $locus = Hum::Ace::Locus->new;
        $locus->name(get_first_attrib_value($gene, 'name'));
        $locus->ensembl_dbID($gene->dbID);

        unless ($gene->source eq 'havana') {
            $locus->gene_type_prefix($gene->source);
        }

        $locus->description( $gene->description);
        $locus->is_truncated($gene->truncated_flag) if $gene->truncated_flag;
        $locus->known(       $gene->is_known)       if $gene->is_known;
        $locus->otter_id(    $gene->stable_id);
        $locus->author_name( $gene->gene_author->name);

        $self->_add_attributes_to_HumAce($gene => 'synonym',       $locus => 'set_aliases');
        $self->_add_attributes_to_HumAce($gene => 'remark',        $locus => 'set_remarks');
        $self->_add_attributes_to_HumAce($gene => 'hidden_remark', $locus => 'set_annotation_remarks');

        foreach my $tsct (@{$gene->get_all_Transcripts}) {

            my $subseq = Hum::Ace::SubSeq->new;
            $subseq->name(get_first_attrib_value($tsct, 'name'));
            $subseq->ensembl_dbID($tsct->dbID);

            $subseq->Locus($locus);
            $subseq->clone_Sequence($assembly->Sequence);

            $subseq->author_name($tsct->transcript_author->name);
            $subseq->strand(     $tsct->strand);
            $subseq->otter_id(   $tsct->stable_id);

            my $translation = $tsct->translation;
            if ($translation) {
                $subseq->translation_region($translation->genomic_start, $translation->genomic_end);
                $subseq->translation_otter_id($translation->stable_id);
            }

            $self->_add_attributes_to_HumAce($tsct => 'remark',        $subseq => 'set_remarks');
            $self->_add_attributes_to_HumAce($tsct => 'hidden_remark', $subseq => 'set_annotation_remarks');

            foreach my $exon (@{$tsct->get_all_Exons}) {

                my $ha_exon = Hum::Ace::Exon->new;
                $ha_exon->ensembl_dbID($exon->dbID);

                $ha_exon->start(   $exon->start);
                $ha_exon->end(     $exon->end);
                $ha_exon->otter_id($exon->stable_id);

                $subseq->add_Exon($ha_exon);
            }

            # partial DUP from fill_transcript_AceText() above
            # mRNA and CDS start not found tags
            if (get_first_attrib_value($tsct, 'cds_start_NF')) {

                $translation
                or confess sprintf("Transcript '%s' has 'CDS start not found' set, but does not have a Translation",
                                   $subseq->name);

                my $first_exon_phase = $translation->start_Exon->phase;

                my $ace_phase = $ens2ace_phase{$first_exon_phase}
                or confess "No Ace phase for Ensembl exon phase '$first_exon_phase'";

                $subseq->start_not_found($ace_phase);
            }
            elsif (get_first_attrib_value($tsct, 'mRNA_start_NF')) {
                $subseq->utr_start_not_found(1);
            }

            # mRNA and CDS end not found tags
            if (get_first_attrib_value($tsct, 'cds_end_NF') or
                get_first_attrib_value($tsct, 'mRNA_end_NF'))
            {
                $subseq->end_not_found(1);
            }

            # DUP from make_ace_genes_transcripts() above
            my $method_name = sprintf('%s%s',
                                      biotype_status2method($tsct->biotype, $tsct->status),
                                      $gene->truncated_flag ? '_trunc' : '');
            my $method = $name_method{$method_name};
            unless ($method) {
                confess "No transcript Method called '$method_name'";
            }
            $subseq->GeneMethod($method);

            # DUP Hum::Ace::SubSeq->process_ace_start_end_transcript_seq()
            my %evidence;
            foreach my $ev (@{$tsct->evidence_list}) {
                push @{$evidence{$ev->type}}, $ev->name;
            }
            foreach my $type (keys %evidence) {
                $subseq->add_evidence_list($type, $evidence{$type});
            }

            # Flag that the sequence is in the db - CHECK ME!!
            $subseq->is_archival(1);

            $assembly->add_SubSeq($subseq);
        }
    }

    return $assembly;
}

sub _add_attributes_to_HumAce {
    my ($self, $vega_obj, $attrib_code, $hum_obj, $hum_method) = @_;

    my @values = map { $_->value } @{$vega_obj->get_all_Attributes($attrib_code)};
    $hum_obj->$hum_method(@values);

    return;
}

1;

__END__

=head1 NAME - Bio::Vega::Region::Ace

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

