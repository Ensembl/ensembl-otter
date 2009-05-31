package Bio::Vega::Converter;

use strict;
use warnings;
use Carp qw{ cluck confess };

use Bio::Vega::Transform::Otter;
use Hum::Ace::AceText;
use Bio::Vega::Utils::GeneTranscriptBiotypeStatus 'biotype_status2method';

my %ace2ens_phase = (
    1   => 0,
    2   => 2,
    3   => 1,
    );

my %ens2ace_phase = (
    0   => 1,
    2   => 2,
    1   => 3,
    );


sub XML_to_ace {
    my ($xml, $dataset_name) = @_;

    my $parser = Bio::Vega::Transform::Otter->new;
    $parser->parse($xml);

    ### Where should we add "-D" commands to the ace data?

    # Assembly object from chromosome slice
    my $ace_str = make_ace_assembly($parser, $dataset_name);
    
    # Objects for each genomic clone
    $ace_str .= make_ace_contigs($parser);
    
    # Genes and transcripts
    $ace_str .= make_ace_genes_transcripts($parser);
    
    # Authors - we only store the author name
    
    # Genomic features
    $ace_str .= make_ace_genomic_features($parser);
    
    
    # Assembly tags
}

sub make_ace_genes_transcripts {
    my ($parser) = @_;
    
    my $slice_name = $parser->get_ChromosomeSlice->name;
    my $slice_ace = Hum::Ace::AceText->new_from_class_and_name('Sequence', $slice_name);
    my $tsct_str  = '';
    my $gene_str  = '';
    
    foreach my $gene (@{$parser->get_Genes}) {
        my $gene_name = $gene->name;
        my $gene_ace = Hum::Ace::AceText->new_from_class_and_name('Locus', $gene_name);
        fill_locus_AceText($gene, $gene_ace);
        
        foreach my $tsct (@{$gene->get_all_Transcripts}) {
            my $name = get_first_attrib_value($tsct, 'name') || $tsct->stable_id;
            confess "No name for transcript ", $tsct->dbID unless $name;
            $gene_ace->add_tag('Positive_sequence', $name);
            my @start_end = ($tsct->start, $tsct->end);
            if ($tsct->strand == -1) {
                @start_end = reverse @start_end;
            }
            $slice_ace->add_tag('SubSequence', $name, @start_end);

            my $tsct_ace = Hum::Ace::AceText->new_from_class_and_name('Sequence', $name);
            $tsct_ace->add_tag('Source', $slice_name);
            $tsct_ace->add_tag('Locus', $gene_name);
                        
            fill_transcript_AceText($tsct, $tsct_ace);
            
            $tsct_str .= $tsct_ace->ace_string;
        }
    }
    
    return join("\n", $slice_ace->ace_string, $tsct_str, $gene_str);
}

sub add_attributes_to_Ace {
    my ($obj, $attrib_code, $ace, $ace_key) = @_;
    
    foreach my $attrib (@{$obj->get_all_Attributes($attrib_code)}) {
        $ace->add_tag($ace_key, $attrib->value);
    }
}

sub get_first_attrib_value {
    my ($obj, $attrib_code) = @_;
    
    if (my ($attrib) = @{$obj->get_all_Attributes($attrib_code)} {
        return $attrib->value;
    } else {
        return;
    }
}

my %ens2ace_phase = (
    0   => 1,
    2   => 2,
    1   => 3,
    );

sub fill_transcript_AceText {
    my ($tsct, $ace) = @_;
    
    if (my $stable = $tsct->stable_id) {
        $ace->add_tag('Transcript_id', $stable);
    }
    
    if (my $author = $tsct->transcript_author) {
        $ace->add_tag('Transcript_author', $author->name);
    }
    
    my $prefix = $tsct->source eq 'havana'
        ? ''
        : $tsct->source . ':';
    my $method = $prefix . biotype_status2method($tsct->biotype, $tsct->status)
    $ace->add_tag('Method', $method);

    add_attributes_to_Ace($tsct, 'remark',        $ace, 'Remark');
    add_attributes_to_Ace($tsct, 'hidden_remark', $ace, 'Annotation_remark');
    
    # Translation start and end
    if (my $translation = $tran->translation) {
        $ace->add_tag('Translation_id', $translation->stable_id);
        $acc
        $str .= sprintf qq{Translation_id "%s"\n}, $translation->stable_id;
        $str .= "CDS ";
        if ($strand == 1) {
            $ace->add_tag('CDS',
                mRNA_posn($tsct, $tran->coding_region_start),
                mRNA_posn($tsct, $tran->coding_region_end),
                );
        } else {
            $ace->add_tag('CDS',
                mRNA_posn($tsct, $tran->coding_region_end),
                mRNA_posn($tsct, $tran->coding_region_start),
                );
        }
    }
    elsif ($method =~ /pseudo/i) {
        $ace->add_tag('CDS');
        $ace->add_tag('Pseudogene');
    }
    
    # Exon locations and stable IDs
    my $exons = $tran->get_all_Exons;
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
        my $first_exon_phase = $exons->[0]->phase;
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
}

sub make_ace_assembly {
    my ($parser, $dataset_name) = @_;
    
    my $chr_slice = $parser->get_ChromosomeSlice;
    my $slice_name = $chr_slice->name;

    my $ace = Hum::Ace::AceText->new_from_class_and_name('Sequence', $slice_name);
    $ace->add_tag('Assembly');
    $ace->add_tag('Species', $dataset_name);
    
    $ace->add_tag('Assembly_name', $chr_slice->seq_region_name);
    
    # Tiles are returned sorted in ascending order by their starts
    my @asm_tiles = $parser->get_Tiles;
    
    # For contigs which contribute more than once to the assembly
    # we need to record their spans for the Smap tags.
    my %ctg_spans;
    foreach my $tile (@asm_tiles) {
        my ($chr_start, $chr_end, $ctg_slice) = @$tile;
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
    my $chr_offset = $asm_tiles[0][0] - 1;
    foreach my $tile ($parser->get_Tiles) {
        my ($chr_start, $chr_end, $ctg_slice, $attrib_list) = @$tile;
        my $name = $ctg_slice->seq_region_name;
        my ($span_start, $span_end) = $ctg_spans{$name};
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
    my ($parser) = @_;
    
    my $str = '';
    foreach my $tile ($parser->get_Tiles) {
        $str .= make_ace_ctg($tile);
    }
    return $str;
}

sub make_ace_ctg {
    my ($chr_start, $chr_end, $ctg_slice, $attrib_list) = @{shift};
    
    ### Authors don't get parsed from the XML
    
    my $ace = Hum::Ace::Text->new_from_class_and_name('Sequence', $ctg_slice->seq_region_name);
    foreach my $at ($attrib_list) {
        my $code  = $at->code;
        my $value = $at->value;
        if ($code eq 'description') {
            $ace->add_tag('EMBL_dump_info', 'DE_line', $value);
        }
        elsif ($code eq 'annotated' and $value eq 'T') {
            $ace->add_tag('Annotation_remark', 'annotated');
        }
        elsif ($code eq 'hidden_remark') {
            $ace->add_tag('Annotation_remark', $value);
        }
        elsif ($code eq 'intl_clone_name') {
            $ace->add_tag('Clone', $value);
        }
        elsif ($code eq 'embl_acc') {
            $ace->add_tag('Accession', $value);
        }
        elsif ($code eq 'embl_sv') {
            $ace->add_tag('Sequence_version', $value);
        }
        elsif ($code eq 'keyword') {
            ### Keywords should be turned off once they are
            ### automatically added to EMBL dumps from otter.
            $ace->add_tag('Keyword', $value);
        }
    }
    
    return $ace->ace_string;
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
    my ($parser) = @_;
    
    
}


# # Features (polyA signals and sites etc...)
# if (defined $feature_set->[0]) {
#     foreach my $sf (@$feature_set) {
#         my $start = $sf->start;
#         my $end   = $sf->end;
#         if ($sf->strand == -1) {
#             ($start, $end) = ($end, $start);
#         }
#         my $type  = $sf->analysis->logic_name or die "no logic_name on analysis object";
#         my $score = $sf->score;
#         $score = 1 unless defined $score;
#         if (my $label = $sf->display_label) {
#             $str .= qq{Feature "$type" $start $end $score "$label"\n};
#         } else {
#             $str .= qq{Feature "$type" $start $end $score\n};
#         }
#     }
# }


1;

__END__

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

