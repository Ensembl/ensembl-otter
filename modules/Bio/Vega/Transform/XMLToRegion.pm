=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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


### Bio::Vega::Transform::XMLToRegion

package Bio::Vega::Transform::XMLToRegion;

use strict;
use warnings;

use Carp;
use NEXT;

use Bio::Vega::Region;
use Bio::Vega::Exon;
use Bio::Vega::Transcript;
use Bio::Vega::Gene;
use Bio::Vega::Translation;
use Bio::EnsEMBL::SimpleFeature;
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::Slice;
use Bio::EnsEMBL::DBEntry;
use Bio::Vega::Author;
use Bio::Vega::ContigInfo;
use Bio::Vega::Evidence;
use Bio::Vega::Utils::Attribute                   'make_EnsEMBL_Attribute';
use Bio::Vega::Utils::GeneTranscriptBiotypeStatus 'method2biotype_status';
use Bio::Otter::Lace::CloneSequence;

use base 'Bio::Vega::XML::Parser';

my (
    %region,
    %analysis_from_transcript_class,

    # Temporaries, used during parsing
    %exon_list,
    %evidence_list,
    %transcript_list,
    %xref_list,
    %logic_ana,
    %seen_transcript_name,
    %seen_gene_name,
    %chromosome_name,
    %author_cache,

    %coord_system_factory,
);


sub DESTROY {
    my ($self) = @_;

    delete $region{$self};
    delete $analysis_from_transcript_class{$self};
    delete $exon_list{$self};
    delete $evidence_list{$self};
    delete $transcript_list{$self};
    delete $xref_list{$self};
    delete $logic_ana{$self};
    delete $seen_gene_name{$self};
    delete $seen_transcript_name{$self};
    delete $chromosome_name{$self};
    delete $author_cache{$self};

    $self->NEXT::DESTROY;

    return;
}

# initialize the parser with methods

sub initialize {
    my ($self) = @_;

    # Register the tags that trigger the building of objects
    $self->object_builders(
        {
            exon                => '_build_Exon',
            transcript          => '_build_Transcript',
            locus               => '_build_Locus',
            evidence            => '_build_Evidence',
            feature             => '_build_Feature',
            xref                => '_build_XRef',
            sequence_fragment   => '_build_SequenceFragment',
            otter               => '_save_species',

            # We don't currently do anything on encountering
            # these end tags:
            exon_set            => '_do_nothing',
            evidence_set        => '_do_nothing',
            feature_set         => '_do_nothing',
        }
    );

    $self->set_multi_value_tags([
        [ locus             => qw{ remark synonym } ],
        [ transcript        => qw{ remark         } ],
        [ sequence_fragment => qw{ remark keyword } ],
    ]);

    # Create our empty region
    $region{$self} = Bio::Vega::Region->new;

    return;
}

sub parse {
    my ($self, @args) = @_;

    # parent does the hard work...
    $self->NEXT::parse(@args);

    # ...calling our builders to assemble the result:
    return $region{$self};
}

sub parsefile {
    my ($self, @args) = @_;

    # parent does the hard work...
    $self->NEXT::parsefile(@args);

    # ...calling our builders to assemble the result:
    return $region{$self};
}


## parser builder methods to build otter objects


sub _save_species {             ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self, $data) = @_;

    $region{$self}->species($data->{'species'});

    return;
}

sub _build_SequenceFragment {   ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self, $data) = @_;

    $self->_create_or_extend_chr_slice($data);
    $self->_build_clone_sequence($data);

    return;
}

sub _create_or_extend_chr_slice {
    my ($self, $data) = @_;

    my $assembly_type = $self->parent_data->{'assembly_type'};

        $chromosome_name{$self} = $data->{'chromosome'};

    my $start          = $data->{'assembly_start'};
    my $end            = $data->{'assembly_end'};

    unless ($assembly_type && $start && $end) {
        die "XML does not contain information needed to create slice:\n"
           ."assembly_type='$assembly_type' start='$start' end='$end'";
    }

    my $chr_coord_system = $self->coord_system_factory->coord_system($data->{coord_system_name});

    if (my $chr_slice = $self->_chr_slice) {
        # Extend the cached version of the slice:
        # We have to make a new slice, because slice parameter methods are read-only
        my $new_chr_slice = Bio::EnsEMBL::Slice->new(
            -seq_region_name   => $assembly_type,
            -start             => $start < $chr_slice->start ? $start : $chr_slice->start,
            -end               => $end   > $chr_slice->end   ? $end   : $chr_slice->end,
            -strand            => 1,
            -coord_system      => $chr_coord_system,
        );
        $self->_chr_slice($new_chr_slice);
    } else {
        # Create the first version of the Slice
        $chr_slice = Bio::EnsEMBL::Slice->new(
            -seq_region_name   => $assembly_type,
            -start             => $start,
            -end               => $end,
            -strand            => 1,
            -coord_system      => $chr_coord_system,
        );
        $self->_chr_slice($chr_slice);
    }
    return;
}

sub _chr_slice {
    my ($self, @args) = @_;
    $region{$self}->slice(@args) if @args;
    return $region{$self}->slice;
}

sub _build_clone_sequence {
    my ($self, $data) = @_;

    my $frag_offset    = $data->{'fragment_offset'};
    my $strand         = $data->{'fragment_ori'};
    my $ctg_name       = $data->{'id'};
    my $cln_length     = $data->{'clone_length'};

    unless ($frag_offset && $strand && $ctg_name && $cln_length) {
        die "XML does not contain information needed to create clone_sequence:\n"
           ."frag_offset='$frag_offset' strand='$strand' "
           ."ctg_name='$ctg_name' cln_length='$cln_length'";
    }

    my $start          = $data->{'assembly_start'};
    my $end            = $data->{'assembly_end'};

    my $cmp_start  = $frag_offset;
    my $cmp_end    = $frag_offset + $end - $start;

    my $accession = $data->{'accession'};
    my $sv        = $data->{'version'};
    my $intl_clone_name = $data->{'clone_name'} || "$accession.$sv";

    my $cln_attrib_list = [
        make_EnsEMBL_Attribute('embl_acc', $accession),
        make_EnsEMBL_Attribute('embl_version', $sv),
        make_EnsEMBL_Attribute('intl_clone_name', $intl_clone_name),
        ];

    # make clone-info attributes from remark and keyword
    my $remarks = $data->{'remark'};
    foreach my $rem (@$remarks){
        my $cln_attrib;
        if ($rem =~ /EMBL_dump_info.DE_line-\s+(.+)/) {
            $cln_attrib = make_EnsEMBL_Attribute('description', $1);
        } elsif ($rem =~ /Annotation_remark-\s+(.+)/) {
            $rem = $1;
            if ($rem =~ /annotated/){
                $cln_attrib = make_EnsEMBL_Attribute('annotated', 'T');
            } else {
                $cln_attrib = make_EnsEMBL_Attribute('hidden_remark', $rem);
            }
        } else {
            $cln_attrib = make_EnsEMBL_Attribute('remark',  $rem);
        }
        push @$cln_attrib_list, $cln_attrib;
    }

    my $keywords = $data->{'keyword'};
    foreach my $keyword (@$keywords) {
        my $cln_attrib = make_EnsEMBL_Attribute('keyword', $keyword);
        push @$cln_attrib_list, $cln_attrib;
    }

        ## FIXME: $cln_author may be passed in the XML, but is ultimately ignored by write_region
    my $cln_author=$self->_make_Author('dummy', 'dummy');

    # create tiles (offset_in_slice + contig_component_slice + attributes)
    my $ctg_cmp_slice = Bio::EnsEMBL::Slice->new(
        -seq_region_name    => $ctg_name,
        -start              => $cmp_start,
        -end                => $cmp_end,
        -strand             => $strand,
        -seq_region_length  => $cln_length,
        -coord_system       => $self->coord_system_factory->coord_system('contig') || $self->coord_system_factory->coord_system('dna_contig') || $self->coord_system_factory->coord_system('primary_assembly')
    );

    my $cs = Bio::Otter::Lace::CloneSequence->new;
    $cs->chromosome(   $chromosome_name{$self});
    $cs->contig_name(  $ctg_name              );
    $cs->accession(    $accession             );
    $cs->sv(           $sv                    );
    $cs->clone_name(   $intl_clone_name       );
    $cs->chr_start(    $start                 );
    $cs->chr_end(      $end                   );
    $cs->contig_start( $cmp_start             );
    $cs->contig_end(   $cmp_end               );
    $cs->contig_strand($strand                );
    $cs->length(       $cln_length            );

    my $ci = Bio::Vega::ContigInfo->new(
        -slice      => $ctg_cmp_slice,
        -author    => $cln_author, # see FIXME above about $cln_author
        -attributes => $cln_attrib_list,
        );
    $cs->ContigInfo($ci);

    $region{$self}->add_clone_sequences($cs);

    return;
}

# FIXME: dup with FromHumAce
sub _get_Analysis {
    my ($self, $name) = @_;

    my $ana =   $logic_ana{$self}{$name}
            ||= Bio::EnsEMBL::Analysis->new(
        -logic_name => $name,
        -gff_source => $name,
                );
    return $ana;
}

sub _build_Evidence {           ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self, $data) = @_;

    my $evidence = Bio::Vega::Evidence->new(
        -name     => $data->{'name'},
        -type     => $data->{'type'},
    );
    my $list = $evidence_list{$self} ||= [];
    push @$list, $evidence;

    return;
}

sub _build_XRef {               ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self, $data) = @_;

    my $xref = Bio::EnsEMBL::DBEntry->new(
        -primary_id     => $data->{'primary_id'},
        -display_id     => $data->{'display_id'},
        -version        => $data->{'version'},
        -release        => $data->{'release'},
        -dbname         => $data->{'dbname'},
        -description    => $data->{'description'},
        );

    my $list = $xref_list{$self} ||= [];
    push @$list, $xref;

    return;
}

sub _build_Feature {            ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self, $data) = @_;

    my $ana = $self->_get_Analysis($data->{'type'});
    my $chr_slice = $self->_chr_slice;

       ##convert xml coordinates which are in chromosomal coords - to feature coords
    my $slice_offset = $chr_slice->start - 1;

    my $feature = Bio::EnsEMBL::SimpleFeature->new(
        -start         => $data->{'start'} - $slice_offset,
        -end           => $data->{'end'}   - $slice_offset,
        -strand        => $data->{'strand'},
        -analysis      => $ana,
        -score         => $data->{'score'},
        -display_label => $data->{'label'} || 'rank = filler',
        -slice         => $chr_slice,
    );
    $region{$self}->add_seq_features($feature);

    return;
}

sub _build_Exon {               ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self, $data) = @_;

    my $chr_slice = $self->_chr_slice;

    my $exon = Bio::Vega::Exon->new(
        -start     => $data->{'start'},
        -end       => $data->{'end'},
        -strand    => $data->{'strand'},
        -stable_id => $data->{'stable_id'},
        -slice     => $chr_slice,
    );

    my $phase=$data->{'phase'};
    my $end_phase=$data->{'end_phase'};

    if (defined($phase)) {
        $exon->phase($phase);
    }else {
        $exon->phase(-1);
    }
    if (defined($end_phase)){
        $exon->end_phase($end_phase);
    } else {
        $exon->end_phase(-1);
    }
    my $list = $exon_list{$self} ||= [];
    push @$list, $exon;

    return;
}

sub add_xrefs_to_object {
    my ($self, $obj) = @_;

    my $xref_list = delete($xref_list{$self})
        or return;
    foreach my $xref (@$xref_list) {
        $obj->add_DBEntry($xref);
    }

    return;
}

sub _build_Transcript {         ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self, $data) = @_;

    my $exons = delete $exon_list{$self};
    my $chr_slice = $self->_chr_slice;

    my $logic_name;
    if ($self->analysis_from_transcript_class) {
        $logic_name = $data->{'transcript_class'};
    } else {
        $logic_name = $data->{'analysis'};
    }
    my $ana = $self->_get_Analysis($logic_name || 'Otter');

    my $transcript = Bio::Vega::Transcript->new(
        -stable_id => $data->{'stable_id'},
        -analysis  => $ana,
        -slice     => $chr_slice,
        );

    $self->add_xrefs_to_object($transcript);

    ##translation start - end
    my $tran_start_pos = $data->{'translation_start'};
    my $tran_end_pos   = $data->{'translation_end'};

    ##adding exon to transcript and finding translation position
    my ($start_Exon,$start_Exon_Pos,$end_Exon,$end_Exon_Pos);
    foreach my $exon (@$exons) {
        $transcript->add_Exon($exon);
        if ( defined $tran_start_pos && !defined $start_Exon_Pos){
            $start_Exon_Pos=$self->translation_pos($tran_start_pos,$exon);
            $start_Exon=$exon;
        }
        if (defined $tran_end_pos && !defined $end_Exon_Pos){
            $end_Exon_Pos=$self->translation_pos($tran_end_pos,$exon);
            $end_Exon=$exon;
        }
    }

    ##add translation to transcript
    if (defined $tran_start_pos && defined $tran_end_pos ){
        if (!defined($start_Exon) || !defined($end_Exon)) {
            die "\n ERROR: Failed mapping translation to transcript with stable_id:".$data->{'stable_id'}.
                "\n undefined start exon:$start_Exon or undefined end exon:$end_Exon\n";
        }
        else {
            my $translation = Bio::Vega::Translation->new(
                -stable_id=>$data->{'translation_stable_id'},
                );
            $translation->start_Exon($start_Exon);
            $translation->start($start_Exon_Pos);
            $translation->end_Exon($end_Exon);
            $translation->end($end_Exon_Pos);

            # TO DO: decide whether is this kludge is necessary and remove it if not
            ##probably add a check to see if $end_Exon_Pos is set or not
            # if ($start_Exon->strand == 1 && $start_Exon->start != $tran_start_pos) {
            #   $start_Exon->end_phase(($start_Exon->length-$start_Exon_Pos+1)%3);
            # } elsif ($start_Exon->strand == -1 && $start_Exon->end != $tran_start_pos) {
            #   $start_Exon->end_phase(($start_Exon->length-$start_Exon_Pos+1)%3);
            # }

            if ($end_Exon->length > $end_Exon_Pos) {
                $end_Exon->end_phase(-1);
            }
            $transcript->translation($translation);
        }
    }
    elsif (defined $tran_start_pos || defined $tran_end_pos) {
        die "ERROR: Only half of translation start/ end pair is defined\n";
    }

    # biotype and status from transcript class name
    if (my $class = $data->{'transcript_class'}) {
        my ($biotype, $status) = method2biotype_status($class);
        $transcript->biotype($biotype);
        $transcript->status($status);
    }
    if (my $source = $data->{'source'}) {
      $transcript->source($source);
    }

    if ($data->{'author'}) {
        my $transcript_author = $self->_make_Author($data->{'author'}, $data->{'author_email'});
        $transcript->transcript_author($transcript_author);
    }

    ##add transcript attributes
    $transcript->add_Attributes($self->_build_transcript_attributes($data, $start_Exon_Pos));

    ##evidence
    my $evidence_l = delete $evidence_list{$self} || [];
    $transcript->evidence_list($evidence_l);

    my $list = $transcript_list{$self} ||= [];
    push @$list, $transcript;

    return;
}

sub _build_transcript_attributes
{
    my ($self, $data, $start_Exon_Pos) = @_;

    my $transcript_name = $data->{'name'};

    my @transcript_attributes;
    if (my $mRNA_start_not_found = $data->{'mRNA_start_not_found'}) {
        push @transcript_attributes, make_EnsEMBL_Attribute('mRNA_start_NF', $mRNA_start_not_found);
    }
    if (my $mRNA_end_not_found = $data->{'mRNA_end_not_found'}) {
        push @transcript_attributes, make_EnsEMBL_Attribute('mRNA_end_NF', $mRNA_end_not_found);
    }
    if (my $cds_start_not_found = $data->{'cds_start_not_found'}) {
        if ($start_Exon_Pos != 1) {
            die "Transcript '$transcript_name' has CDS start not found set but has 5' UTR";
        }
        push @transcript_attributes, make_EnsEMBL_Attribute('cds_start_NF', $cds_start_not_found);
    }
    if (my $cds_end_not_found = $data->{'cds_end_not_found'}) {
        push @transcript_attributes, make_EnsEMBL_Attribute('cds_end_NF', $cds_end_not_found);
    }

    if(my $remarks=$data->{'remark'}) {
        foreach my $rem (@$remarks){
            my $attrib;
            if($rem=~/Annotation_remark-\s+(.+)/) {
                $rem=$1;
                $attrib=make_EnsEMBL_Attribute('hidden_remark', $rem);
            } else {
                $attrib=make_EnsEMBL_Attribute('remark', $rem);
            }
            push @transcript_attributes,$attrib;
        }
    }

    if ($transcript_name) {   ### Don't we always have a name?
        if ($seen_transcript_name{$self}{$transcript_name}) {
            die "more than one transcript has the name $transcript_name";
        } else {
            $seen_transcript_name{$self}{$transcript_name} = 1;
        }
        my $attrib=make_EnsEMBL_Attribute('name', $transcript_name);
        push @transcript_attributes,$attrib;
    }

    return @transcript_attributes;
}

sub translation_pos {
  my ($self, $loc, $exon) = @_;
  if (($exon->start <= $loc) && ($loc <= $exon->end)) {
     if ($exon->strand == 1) {
        return $loc - $exon->start + 1;
     } else {
        return $exon->end - $loc + 1;
     }
  } else {
     return;
  }
}

sub _build_Locus {              ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self, $data) = @_;

    ## version and is_current ??
    my $transcripts = delete $transcript_list{$self};
    ## transcript author group has been temporarily set to 'anything' ??

    my $chr_slice = $self->_chr_slice;
    my $ana = $self->_get_Analysis($data->{'analysis'} || 'Otter');
    my $gene = Bio::Vega::Gene->new(
        -stable_id => $data->{'stable_id'},
        -slice => $chr_slice,
        -description => $data->{'description'},
        -analysis => $ana,
        );

    $self->add_xrefs_to_object($gene);

    # biotype, source & status framed from gene type
    my ($source, $type);
    if (my $gene_type = $data->{'type'}) {
        if ($gene_type =~ /(\S+):(.+)/){
            ##in future source will be a tag on itself indicating authority equivalent to group name
            $source = $1;
            $type   = $2;
        } else {
            $source = 'havana';
            $type   = $gene_type;
        }
    } else {
        die "Gene type missing";
    }
    my ($biotype, $status) = method2biotype_status($type);
    $status = 'KNOWN' if $data->{'known'};

    if (my $gene_source = $data->{source}) {
      $source = $gene_source;
    }
    $gene->source($source);
    $gene->biotype($biotype);
    $gene->status($status);

    if ($data->{'author'}) {
        my $gene_author = $self->_make_Author($data->{'author'}, $data->{'author_email'});
        $gene->gene_author($gene_author);
    }

    ##share exons among transcripts of this gene
    foreach my $tran (@$transcripts) {
        $gene->add_Transcript($tran);
    }
    $gene->prune_Exons;
    ##add all gene attributes
    $gene->add_Attributes($self->_build_gene_attributes($data));
    ##truncated flag
    my $truncated=$data->{'truncated'};
    if (defined $truncated) {
        $gene->truncated_flag($truncated);
        $gene->add_truncated_attribute if $truncated;
    }

    #convert coordinates from chromosomal coordinates to slice coordinates

    my $slice_offset = $chr_slice->start - 1;

    foreach my $exon (@{$gene->get_all_Exons}) {
        $exon->start($exon->start - $slice_offset);
        $exon->end(  $exon->end   - $slice_offset);
    }

    foreach my $transcript (@$transcripts){
        $transcript->start($transcript->start - $slice_offset);
        $transcript->end(  $transcript->end   - $slice_offset);

        my $logic_name = $transcript->analysis->logic_name;
        if ($self->analysis_from_transcript_class and $source ne 'havana' and $source ne 'ensembl_havana' and $logic_name ne 'Otter') {
            $logic_name = sprintf('%s:%s', $source, $logic_name);
        }
        if ($truncated) {
            # update analysis to _trunc version
            $logic_name .= '_trunc';
        }
        if ($logic_name ne $transcript->analysis->logic_name) {
            $transcript->analysis($self->_get_Analysis($logic_name));
        }
    }

    $gene->start($gene->start - $slice_offset);
    $gene->end(  $gene->end   - $slice_offset);

    $region{$self}->add_genes($gene);

    return;
}

sub _build_gene_attributes
{
    my ($self, $data) = @_;

    my @gene_attributes;

    my $gene_name=$data->{'name'};
    if (defined $gene_name ) {
        if ($seen_gene_name{$self}{$gene_name}) {
            die "more than one gene has the name $gene_name";
        } else {
            $seen_gene_name{$self}{$gene_name} = 1;
        }
        my $name_attrib=make_EnsEMBL_Attribute('name', $gene_name);
        push @gene_attributes,$name_attrib;
    }
    my $gene_synonym=$data->{'synonym'};
    if (defined $gene_synonym){
        foreach my $a (@$gene_synonym) {
            my $syn_attrib=make_EnsEMBL_Attribute('synonym', $a);
            push @gene_attributes,$syn_attrib;
        }
    }

    if(my $remarks=$data->{'remark'}) {
        foreach my $rem (@$remarks){
            my $attrib;
            if($rem=~/Annotation_remark-\s+(.+)/) {
                $rem=$1;
                $attrib=make_EnsEMBL_Attribute('hidden_remark', $rem);
            } else {
                $attrib=make_EnsEMBL_Attribute('remark', $rem);
            }
            push @gene_attributes,$attrib;
        }
    }
    return @gene_attributes;
}

sub _do_nothing {               ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    return;
}


##make Otter objects methods

sub _make_Author {
    my ($self, $name, $email) = @_;

    $email ||= $name;

    my $author;
    unless ($author = $author_cache{$self}{$email}) {
        $author = Bio::Vega::Author->new (
            -name   => $name,
            -email  => $email,
        );
        $author_cache{$self}{$email} = $author;
    }
    return $author;
}

sub coord_system_factory {
    my ($self, @args) = @_;
    ($coord_system_factory{$self}) = @args if @args;
    my $coord_system_factory = $coord_system_factory{$self};
    return $coord_system_factory;
}

## accessor


sub analysis_from_transcript_class {
    my ($self, @args) = @_;
    ($analysis_from_transcript_class{$self}) = @args if @args;
    my $analysis_from_transcript_class = $analysis_from_transcript_class{$self};
    return $analysis_from_transcript_class;
}

1;

__END__

=head1 NAME - Bio::Vega::Transform::XMLToRegion

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

