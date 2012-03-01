
# This module is badly named.  It is nothing to do with Bio::Vega::Transform
# It does not parse XML, it creates XML.

package Bio::Vega::Transform::XML;

use strict;
use warnings;
use Carp;

use Bio::EnsEMBL::Utils::Exception qw (throw);
use Bio::Vega::Utils::GeneTranscriptBiotypeStatus 'biotype_status2method';
use Bio::Otter::Lace::CloneSequence;

use base 'Bio::Vega::Writer';

my (
    %species,
    %slice,
    %otter_dba,
    %genes,
    %seq_features,
    %clone_seq_list,
    %skip_trunc,
    );

sub DESTROY {
    my ($self) = @_;

    delete(                 $species{$self} );
    delete(                   $slice{$self} );
    delete(               $otter_dba{$self} );
    delete(                   $genes{$self} );
    delete(            $seq_features{$self} );
    delete(          $clone_seq_list{$self} );
    delete(              $skip_trunc{$self} );

    # So that any DESTROY methods in base classes get called:
    bless $self, 'Bio::Vega::Writer';

    return;
}

# Use this to sort SimpleFeatures, Genes and Transcripts
# Not actually necessary, but useful when test XML parsing and generation.
my $by_start_end_strand = sub {
    return $a->start      <=> $b->start
        || $a->end        <=> $b->end
        || $a->strand     <=> $b->strand
        || $a->display_id cmp $b->display_id;
};

# get/set methods exposed on object interface

sub species {
    my ($self, @args) = @_;

    $species{$self} = shift @args if @args;
    return $species{$self};
}

sub slice {
    my ($self, @args) = @_;

    $slice{$self} = shift @args if @args;
    return $slice{$self};
}

sub otter_dba {
    my ($self, @args) = @_;

    $otter_dba{$self} = shift @args if @args;
    return $otter_dba{$self};
}

sub genes {
    my ($self, @args) = @_;

    $genes{$self} = shift @args if @args;
    return $genes{$self};
}

sub seq_features {
    my ($self, @args) = @_;

    $seq_features{$self} = shift @args if @args;
    return $seq_features{$self};
}

sub clone_seq_list {
    my ($self, @args) = @_;

    $clone_seq_list{$self} = shift @args if @args;
    return $clone_seq_list{$self};
}

sub skip_truncated_genes {
    my ($self, @args) = @_;

    $skip_trunc{$self} = shift @args if @args;
    return $skip_trunc{$self} || 0;
}

# methods which fetch data from otter db

sub fetch_data_from_otter_db {
    my ($self) = @_;

    confess "Cannot fetch data without slice"     unless $slice{$self};
    confess "Cannot fetch data without otter_dba" unless $otter_dba{$self};

    $self->fetch_CloneSequences;
    $self->fetch_species;
    $self->fetch_SimpleFeatures;
    $self->fetch_Genes;

    return;
}

sub fetch_species {
    my ($self) = @_;

    $species{$self} = $otter_dba{$self}->species;

    return;
}

sub fetch_SimpleFeatures {
    my ($self) = @_;

    my $slice = $slice{$self};
    my $features        = $slice->get_all_SimpleFeatures;
    my $slice_length    = $slice->length;

    # Discard features which overlap the ends of the slice
    for (my $i = 0; $i < @$features; ) {
        my $sf = $features->[$i];
        if ($sf->start < 1 or $sf->end > $slice_length) {
            splice(@$features, $i, 1);
        } else {
            $i++;
        }
    }

    $seq_features{$self} = $features;

    return;
}

sub fetch_Genes {
    my ($self) = @_;

    $genes{$self} = $slice{$self}->get_all_Genes;

    return;
}

sub fetch_CloneSequences {
    my ($self) = @_;

    my $slice_projection = $slice{$self}->project('contig');
    my $cs_list = $clone_seq_list{$self} = [];
    foreach my $contig_seg (@$slice_projection) {
        my $cs = $self->fetch_CloneSeq($contig_seg);
        push @$cs_list, $cs;
    }

    return;
}

sub fetch_CloneSeq {
    my ($self, $contig_seg) = @_;

    my $contig_slice = $contig_seg->to_Slice();

    my $cs = Bio::Otter::Lace::CloneSequence->new;
    $cs->chromosome(get_single_attrib_value($slice{$self}, 'chr'));
    $cs->contig_name($contig_slice->seq_region_name);

    my $clone_slice = $contig_slice->project('clone')->[0]->to_Slice;
    $cs->accession(     get_single_attrib_value($clone_slice, 'embl_acc')           );
    $cs->sv(            get_single_attrib_value($clone_slice, 'embl_version')       );

    if (my ($cna) = @{$clone_slice->get_all_Attributes('intl_clone_name')}) {
        $cs->clone_name($cna->value);
    } else {
        $cs->clone_name($cs->accession_dot_sv);
    }

    my $assembly_offset = $slice{$self}->start - 1;
    $cs->chr_start( $contig_seg->from_start + $assembly_offset  );
    $cs->chr_end(   $contig_seg->from_end   + $assembly_offset  );
    $cs->contig_start(  $contig_slice->start                );
    $cs->contig_end(    $contig_slice->end                  );
    $cs->contig_strand( $contig_slice->strand               );
    $cs->length(        $contig_slice->seq_region_length    );

    if (my $ci = $otter_dba{$self}->get_ContigInfoAdaptor->fetch_by_contigSlice($contig_slice)) {
        $cs->ContigInfo($ci);
    }

    return $cs;
}

sub get_single_attrib_value {
    my ($obj, $code) = @_;

    my $attr = $obj->get_all_Attributes($code);
    if (@$attr == 1) {
        return $attr->[0]->value;
    }
    elsif (@$attr == 0) {
        return;
    }
    else {
        confess sprintf("Got %d %s Attributes on %s",
            scalar(@$attr), $code, ref($obj));
    }
}

sub get_geneXML {
  my ($self, $gene)=@_;

  my $ppobj=$self->generate_Locus($gene,2);
  my $gene_xml=$self->formatxml($ppobj);

  return $gene_xml;
}

sub generate_OtterXML {
    my ($self) = @_;

    my $ot = $self->prettyprint('otter');
    $ot->indent(1);
    my $dataset_name = $species{$self} or confess "No species set";
    $ot->attribvals($self->prettyprint('species', $dataset_name));
    $ot->attribobjs($self->generate_SequenceSet);

    return $self->formatxml($ot);
}

sub generate_SequenceSet {
    my ($self) = @_;

    my $ss=$self->prettyprint('sequence_set');
    $ss->attribvals($self->generate_AssemblyType);

    my $cs_list = $clone_seq_list{$self} || [];
    foreach my $cs (@$cs_list) {
        ### I think we will generate contig attributes multiple times
        ### for contigs which appear multiple times in the assembly
        $ss->attribobjs($self->generate_SequenceFragment($cs));
    }

    $ss->attribobjs($self->generate_FeatureSet);

    my $list_of_genes = $genes{$self} || [];

    # Set fetch_truncated_genes=0 in [client] stanza of config to skip truncated genes.
    if ($skip_trunc{$self}) {
        $list_of_genes = [grep { ! $_->truncated_flag } @$list_of_genes];
    }

    foreach my $gene (sort $by_start_end_strand @$list_of_genes) {
        # warn sprintf "Adding gene %6d .. %6d  %+d  %s\n", $gene->start, $gene->end, $gene->strand, $gene->display_id;
        $ss->attribobjs($self->generate_Locus($gene));
    }
    return $ss;
}

sub generate_AssemblyType {
    my ($self) = @_;

    my $atype = $self->prettyprint('assembly_type', $slice{$self}->seq_region_name);

    return $atype;
}

sub generate_SequenceFragment {
    my ($self, $cs) = @_;

    my $sf = $self->prettyprint('sequence_fragment');
    $sf->attribvals($self->prettyprint('id',                $cs->contig_name    ));
    $sf->attribvals($self->prettyprint('chromosome',        $cs->chromosome     ));
    $sf->attribvals($self->prettyprint('accession',         $cs->accession      ));
    $sf->attribvals($self->prettyprint('version',           $cs->sv             ));
    $sf->attribvals($self->prettyprint('clone_name',        $cs->clone_name     ));
    $sf->attribvals($self->prettyprint('assembly_start',    $cs->chr_start      ));
    $sf->attribvals($self->prettyprint('assembly_end',      $cs->chr_end        ));
    $sf->attribvals($self->prettyprint('fragment_ori',      $cs->contig_strand  ));
    $sf->attribvals($self->prettyprint('fragment_offset',   $cs->contig_start   ));
    $sf->attribvals($self->prettyprint('clone_length',      $cs->length         ));

    if (my $ci = $cs->ContigInfo) {
        # Commented out adding author since this is ignored on client side
        # if (my $contig_author = $ci->author) {
        #     $sf->attribvals($self->prettyprint('author',        $contig_author->name    ));
        #     $sf->attribvals($self->prettyprint('author_email',  $contig_author->email   ));
        # }

        my $ci_attribs = $ci->get_all_Attributes;

        foreach my $cia (@$ci_attribs) {
            if ($cia->code eq 'remark'
            || $cia->code eq 'hidden_remark'
            || $cia->code eq 'annotated'
            || $cia->code eq 'description') {
                my $value = $cia->value;

                if ($cia->code eq 'description') {
                    $value = 'EMBL_dump_info.DE_line- ' . $value;
                }
                if ($cia->code eq 'annotated' && $cia->value eq 'T') {
                    $value = 'Annotation_remark- annotated';
                }
                $sf->attribvals($self->prettyprint('remark', $value));
            }
        }
        foreach my $cia (@$ci_attribs) {
            if ($cia->code eq 'keyword') {
                $sf->attribvals($self->prettyprint('keyword',$cia->value));
            }
        }
    }

    return $sf;
}

sub generate_Locus {
    my ($self, $gene, $indent) = @_;

    return unless $gene;

    my $g=$self->prettyprint('locus');
    if (defined $indent) {
        $g->indent($indent);
    }

    if($gene->stable_id) {
        $g->attribvals($self->prettyprint('stable_id',$gene->stable_id));
    }

    my $gene_description = $gene->description || '';
    $g->attribvals($self->prettyprint('description', $gene_description));

    my $gene_name_att = $gene->get_all_Attributes('name');
    my $gene_name = $gene_name_att->[0] ? $gene_name_att->[0]->value : '';
    $g->attribvals($self->prettyprint('name', $gene_name));

    my ($type) = biotype_status2method($gene->biotype, $gene->status);
    my $source = $gene->source;
    if ($source ne 'havana') {
        $type = "$source:$type";
    }
    $g->attribvals($self->prettyprint('type',$type));

    $g->attribvals($self->prettyprint('known',$gene->is_known || 0));
    $g->attribvals($self->prettyprint('truncated',$gene->truncated_flag));

    if(my $synonyms = $gene->get_all_Attributes('synonym')) {
        foreach my $syn (@$synonyms){
            $g->attribvals($self->prettyprint('synonym',$syn->value));
        }
    }

    if(my $remarks = $gene->get_all_Attributes('remark')) {
        foreach my $rem (@$remarks) {
            $g->attribvals($self->prettyprint('remark',$rem->value));
        }
    }
    if(my $remarks = $gene->get_all_Attributes('hidden_remark')) {
        foreach my $rem (@$remarks) {
            $g->attribvals($self->prettyprint('remark','Annotation_remark- '.$rem->value));
        }
    }

    if (my $gene_author = $gene->gene_author) {
        $g->attribvals($self->prettyprint('author',       $gene_author->name));
        $g->attribvals($self->prettyprint('author_email', $gene_author->email));
    }

    if( my $transcripts=$gene->get_all_Transcripts ) {

        my $coord_offset=$gene->get_all_Exons->[0]->slice->start-1;

        foreach my $tran (sort $by_start_end_strand @$transcripts) {
            $g->attribobjs($self->generate_Transcript($tran, $coord_offset));
        }
    } else {
        throw "Cannot create Otter XML, no transcripts attched to this gene:$gene";
    }

    return $g;
}

sub generate_Transcript {
    my ($self, $tran, $coord_offset)=@_;

    my $t=$self->prettyprint('transcript');
    if($tran->stable_id) {
        $t->attribvals($self->prettyprint('stable_id',$tran->stable_id));
    }

    if (my $tsct_author = $tran->transcript_author) {
        $t->attribvals($self->prettyprint('author',       $tsct_author->name));
        $t->attribvals($self->prettyprint('author_email', $tsct_author->email));
    }

  if(my $remarks = $tran->get_all_Attributes('remark')){
     foreach my $rem (@$remarks){
        $t->attribvals($self->prettyprint('remark',$rem->value));
     }
  }
  if(my $remarks = $tran->get_all_Attributes('hidden_remark')){
      foreach my $rem (@$remarks){
          $t->attribvals($self->prettyprint('remark','Annotation_remark- '.$rem->value));
      }
  }

  $self->add_start_end_not_found_tags($t, $tran);

  ##in future <transcript_class> tag will be replaced by trancript <biotype> and <status> tags
  ##<type> tag will be removed
  my ($class) = biotype_status2method($tran->biotype, $tran->status);
  $t->attribvals($self->prettyprint('transcript_class', $class));

  my $tran_name_att = $tran->get_all_Attributes('name') ;
  my $tran_name='';
  if ($tran_name_att->[0]){
      $tran_name=$tran_name_att->[0]->value;
  }
  $t->attribvals($self->prettyprint('name',$tran_name));

  my $es=$self->generate_EvidenceSet($tran);
  if ($es) {
      $t->attribobjs($es);
  }

  my ($tran_low,$tran_high);
  if (my $translation=$tran->translation){
      my $strand = $translation->start_Exon->strand;
      $tran_low  = $tran->coding_region_start;
      $tran_high = $tran->coding_region_end;
      my ($tl_start, $tl_end) = ($strand == 1)
          ? ($tran_low + $coord_offset, $tran_high + $coord_offset)
          : ($tran_high + $coord_offset, $tran_low + $coord_offset);
      if ($tl_start){
          $t->attribvals($self->prettyprint('translation_start',$tl_start));
      }
      if ($tl_end){
          $t->attribvals($self->prettyprint('translation_end',$tl_end));
      }
      if ($translation->stable_id){
          $t->attribvals($self->prettyprint('translation_stable_id',$translation->stable_id));
      }

  }

  $t->attribobjs($self->generate_ExonSet($tran,$coord_offset));

  return $t;
}

{
    # A bit of pointless mapping between EnsEMBL tag codes and XML tags!
    my @attrib_tag = qw{
        mRNA_start_NF       mRNA_start_not_found
        mRNA_end_NF         mRNA_end_not_found
        cds_start_NF        cds_start_not_found
        cds_end_NF          cds_end_not_found
    };

    sub add_start_end_not_found_tags {
        my ($self, $t, $tran) = @_;

        for (my $i = 0; $i < @attrib_tag; $i += 2) {
            my ($attrib, $tag) = @attrib_tag[$i, $i + 1];
            if (my $val = get_single_attrib_value($tran, $attrib)) {
                $t->attribvals($self->prettyprint($tag, $val));
            }
        }

        return;
    }
}

sub generate_ExonSet {
  my ($self,$tran,$coord_offset)=@_;

  my $exon_set=$tran->get_all_Exons;
  my $exs=$self->prettyprint('exon_set');
  foreach my $exon (@$exon_set){
      my $e=$self->prettyprint('exon');
      if($exon->stable_id) {
          $e->attribvals($self->prettyprint('stable_id',$exon->stable_id));
      }
      $e->attribvals($self->prettyprint('start',$exon->start + $coord_offset));
      $e->attribvals($self->prettyprint('end',$exon->end  + $coord_offset));
      $e->attribvals($self->prettyprint('strand',$exon->strand));
      $e->attribvals($self->prettyprint('phase',$exon->phase));
      $e->attribvals($self->prettyprint('end_phase',$exon->end_phase));
      $exs->attribobjs($e);
  }
  return $exs;
}


sub generate_EvidenceSet {
    my ($self,$tran)=@_;

    my $evidence = $tran->evidence_list;
    return unless @$evidence;

    my $es = $self->prettyprint('evidence_set');
    foreach my $evi (sort {$a->type cmp $b->type || $a->name cmp $b->name} @$evidence) {
        my $e = $self->prettyprint('evidence');
        $e->attribvals($self->prettyprint('name', $evi->name));
        $e->attribvals($self->prettyprint('type', $evi->type));
        $es->attribobjs($e);
    }

    return $es;
}

sub generate_FeatureSet {
  my ($self) = @_;

  my $features = $seq_features{$self} or return;
  my $slice = $slice{$self};

  my $fs=$self->prettyprint('feature_set');
  my $offset=$slice->start-1;

  foreach my $feature (sort $by_start_end_strand @$features) {

      my $f = $self->prettyprint('feature');
      if ($feature->analysis){
          my $a=$feature->analysis;
          $f->attribvals($self->prettyprint('type',$a->logic_name));
      } else {
          throw "Cannot create Otter XML, feature type is absent: $feature";
      }

      if ($feature->start){
          $f->attribvals($self->prettyprint('start',$feature->start+$offset));
      } else {
          throw "Cannot create Otter XML, feature start is absent: $feature";
      }

      if ($feature->end){
          $f->attribvals($self->prettyprint('end',$feature->end+$offset));
      } else {
          throw "Cannot create Otter XML, feature end is absent: $feature";
      }

      if ($feature->strand){
          $f->attribvals($self->prettyprint('strand',$feature->strand));
      } else {
          throw "Cannot create Otter XML, feature strand is absent: $feature";
      }

      if ($feature->score){
          $f->attribvals($self->prettyprint('score',$feature->score));
      }
      if ($feature->display_label){
          $f->attribvals($self->prettyprint('label',$feature->display_label));
      }
      $fs->attribobjs($f);
  }
  return ($fs);
}


sub generate_DNA {
    my ($self, $slice);

    my $dna=$self->prettyprint('dna', $slice->seq);

    return $dna;
}

1;

__END__

=head1 NAME - Bio::Vega::Transform::XML

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

