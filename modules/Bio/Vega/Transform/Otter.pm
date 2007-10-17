### Bio::Vega::Transform::Otter

package Bio::Vega::Transform::Otter;

use strict;
use warnings;
use Carp;
use Bio::Vega::Exon;
use Bio::Vega::Transcript;
use Bio::Vega::Gene;
use Bio::Vega::Translation;
use Bio::EnsEMBL::SimpleFeature;
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::Slice;
use Bio::EnsEMBL::CoordSystem;
use Bio::EnsEMBL::Attribute;
use Bio::Vega::Author;
use Bio::Vega::AuthorGroup;
use Bio::Vega::ContigInfo;
use Bio::Vega::Evidence;
use Bio::Vega::AssemblyTag;
use Bio::Vega::Utils::GeneTranscriptBiotypeStatus 'method2biotype_status';

#use Data::Dumper;   # For debugging
# This misses the "$VAR1 = " bit out from the Dumper() output
#$Data::Dumper::Terse = 1;

use base 'Bio::Vega::Transform';

my (
    %exon_list,
	%evidence_list,
    %gene_list,
	%assembly_tag_list,
    %transcript_list,
    %feature_list,
	%logic_ana,
	%coord_system,
	%slice,
	%seen_transcript_name,
	%seen_gene_name,
	%assembly_type,
    %chromosome_name,
	%dna,
	%assembly,
    %author_cache,
);


sub DESTROY {
    my ($self) = @_;

    delete $exon_list{$self};
    delete $evidence_list{$self};
    delete $gene_list{$self};
    delete $assembly_tag_list{$self};
    delete $transcript_list{$self};
    delete $feature_list{$self};
    delete $logic_ana{$self};
    delete $coord_system{$self};
    delete $slice{$self};
    delete $seen_gene_name{$self};
    delete $seen_transcript_name{$self};
    delete $assembly_type{$self};
    delete $chromosome_name{$self};
    delete $dna{$self};
    delete $assembly{$self};
    delete $author_cache{$self};

        # So that DESTROY gets called in baseclass:
    bless $self, 'Bio::Vega::Transform';
}

##initialize the parser with methods

sub initialize {
  my ($self) = @_;
  # Register the tags that trigger the building of objects
  $self->object_builders(
								 {
								  exon                => 'build_Exon',
								  transcript          => 'build_Transcript',
								  locus               => 'build_Locus',
								  evidence            => 'build_Evidence',
								  feature             => 'build_Feature',
								  assembly_tag        => 'build_AssemblyTag',
								  sequence_fragment   => 'build_SequenceFragment',
								  assembly_type       => 'build_AssemblyType',
								  dna                 => 'build_DNA',
								  # We don't currently do anything on encountering
								  # these end tags:
								  exon_set            => 'do_nothing',
								  evidence_set        => 'do_nothing',
								  feature_set         => 'do_nothing',
								  otter               => 'do_nothing',
								 }
								  );
  $self->set_multi_value_tags([
										 [ locus             => qw{ remark synonym } ],
										 [ transcript        => qw{ remark         } ],
										 [ sequence_fragment => qw{ remark keyword } ],
										]
									  );
  $self->init_builders(
							  {
								otter                  => 'init_CoordSystem_Version',
								vega                   => 'init_CoordSystem_Version',
							  }
							 );

    # means we do not want to load the assembly:
  $self->Assembly('no');
}

    # 'yes'||'no' shows whether the assembly is to be loaded into the DB
sub Assembly {
  my ($self,$value)=@_;

  if(defined $value) {
	 $assembly{$self} = ($value eq 'yes') ? 1 : 0;
  }
  return $assembly{$self};

}


sub init_CoordSystem_Version {
    my ($self,$value)=@_;

    $coord_system{$self}{'version'} ||= $value;
    return $coord_system{$self}{'version'};
}

## parser builder methods to build otter objects

sub build_SequenceFragment {
    my ($self, $data) = @_;

    my $assembly_type = $assembly_type{$self};
    my $chrname       = $chromosome_name{$self} ||= $data->{'chromosome'}; # cached from the previous SequenceFragments

    if(!defined $assembly_type) {
        die "cannot make chromosome slice without assembly type name\n";
    }
    if($chrname ne $data->{'chromosome'}) {
        die " Chromosome names are different - can't make slice [$chrname][".$data->{'chromosome'}."]\n";
    }

    my $offset = $data->{'fragment_offset'};
    my $start  = $data->{'assembly_start'};
    my $end    = $data->{'assembly_end'};
    my $strand = $data->{'fragment_ori'};

    my $cln_coord_system=$self->make_CoordSystem('clone');
    my $ctg_coord_system=$self->make_CoordSystem('contig');
    my $chr_coord_system=$self->make_CoordSystem('chromosome');

    my $chrslice=$self->get_ChromosomeSlice;

    if($chrslice) {

            # extend the cached slice:
        my $slice_start = ($start < $chrslice->start()) ? $start : $chrslice->start();
        my $slice_end   = ($end > $chrslice->end()) ? $end : $chrslice->end();

        unless ($chrname and $start and $end and $offset and $strand) {
        die "XML does not contain information needed to create slice:\n"
           ."chr_name='$chrname'  chr_start='$start'  chr_end='$end' offset='$offset' strand = '$strand'";
        }
        my $new_chr_slice = $self->make_Slice( $assembly_type,
                                            ($self->Assembly() ? 1 : $slice_start),
                                            $slice_end,$slice_end,1,$chr_coord_system);
        $self->set_ChromosomeSlice($new_chr_slice);

    } else {

        $chrslice = $self->make_Slice($assembly_type,
                                      ($self->Assembly() ? 1 : $start),
                                      $end,$end,1,$chr_coord_system);
        $self->set_ChromosomeSlice($chrslice);

            # The following happens only once, and is the only use for $chrname:
        my $chr_attrib=$self->make_Attribute('chr','Chromosome Name','Chromosome Name Contained in the Assembly',$chrname);
        my $chr_attrib_list = $slice{$self}{'chr_attrib'} ||= [];
        push @$chr_attrib_list,$chr_attrib;
    }

    my $cmp_start = $offset;
    my $cmp_end   = $offset + $end - $start;
    my $ctg_name  = $data->{'id'};
    my $cln_length;
    if ($ctg_name =~ /\S+\.\d+\.\d+\.(\d+)/){
        $cln_length=$1;
    }
    unless($start && $end && $strand && $offset && $ctg_name) {
        die "ERROR: Either start:$start or end:$end or strand:$strand or offset:$offset or contig_id:$ctg_name not defined in the xml file\n";
    }

    my $cln_name  = $data->{'accession'}.'.'.$data->{'version'};
    ## make clone-info attributes from remark and keyword
    my $cln_attrib_list=[];

    my $remarks=$data->{'remark'};
    foreach my $rem (@$remarks){
        my $cln_attrib;
        if ($rem =~ /EMBL_dump_info.DE_line-\s+(.+)/) {
            $cln_attrib = $self->make_Attribute('description','EMBL Header Description','',$1);
        } elsif ($rem =~ /Annotation_remark-\s+(.+)/) {
            $rem=$1;
            if ($rem =~ /annotated/){
                $rem=$1;
                $cln_attrib = $self->make_Attribute('annotated','Clone Annotation Status','','T');
            } else {
                $cln_attrib = $self->make_Attribute('hidden_remark','Hidden Remark','',$rem);
            }
        } else {
            $cln_attrib = $self->make_Attribute('remark','Remark','Annotation Remark',$rem);
        }
        push @$cln_attrib_list, $cln_attrib;
    }

    my $keywords=$data->{'keyword'};
    foreach my $keyword (@$keywords) {
        my $cln_attrib = $self->make_Attribute('keyword', 'Clone Keyword', '', $keyword);
        push @$cln_attrib_list,$cln_attrib;
    }

        ##make clone - contig slice
    my $cln_slice = $self->make_Slice($cln_name,1,$cln_length,$cln_length,$strand,$cln_coord_system);
    my $ctg_slice = $self->make_Slice($ctg_name,  1,$cln_length,$cln_length,$strand,$ctg_coord_system);

    my $cln_ctg_piece=[$cln_slice,$ctg_slice];
    my $cln_ctg_list = $slice{$self}{'cln_ctg'} ||= [];
    push @$cln_ctg_list,$cln_ctg_piece;

        ##make chromosome - contig slice
    my $chr_asm_slice = $self->make_Slice($assembly_type,$start,$end,$end,$strand,$chr_coord_system);
    my $ctg_cmp_slice = $self->make_Slice($ctg_name,$cmp_start,$cmp_end,$cmp_end,$strand,$ctg_coord_system);
    my $cln_author=$self->make_Author($data->{'author'}, $data->{'author_email'});

    my $chr_ctg_piece = [$chr_asm_slice,$ctg_cmp_slice,$cln_attrib_list,$cln_author];
    my $chr_ctg_list = $slice{$self}{'chr_ctg'} ||= [];
    push @$chr_ctg_list,$chr_ctg_piece;
}


sub build_Evidence {
    my ($self, $data) = @_;

    my $evidence = Bio::Vega::Evidence->new(
        -name     => $data->{'name'},
        -type     => $data->{'type'},
    );
    my $list = $evidence_list{$self} ||= [];
    push @$list, $evidence;
}

sub build_DNA {
    my ($self, $data) = @_;

    $dna{$self} = $data->{'dna'};
}

sub build_Feature {
    my ($self, $data) = @_;

    my $ana = $logic_ana{$self}{$data->{'type'}} ||= Bio::EnsEMBL::Analysis->new(-logic_name => $data->{'type'});
    my $slice = $self->get_ChromosomeSlice;

       ##convert xml coordinates which are in chromosomal coords - to feature coords
    my $slice_offset = $slice->start - 1;

    my $feature = Bio::EnsEMBL::SimpleFeature->new(
        -start         => $data->{'start'} - $slice_offset,
        -end           => $data->{'end'}   - $slice_offset,
        -strand        => $data->{'strand'},
        -analysis      => $ana,
        -score         => $data->{'score'},
        -display_label => $data->{'label'},
        -slice         => $slice,
    );
    my $list = $feature_list{$self} ||= [];
    push @$list, $feature;
}

sub build_AssemblyTag {
    my ($self, $data) = @_;

    my $slice = $self->get_ChromosomeSlice;

    #convert xml coordinates which are in chromosomal coords - to tag coords
    my $slice_offset = $slice->start - 1;

    my $at = Bio::Vega::AssemblyTag->new(
        -start     => $data->{'contig_start'} - $slice_offset,
        -end       => $data->{'contig_end'}   - $slice_offset,
        -strand    => $data->{'contig_strand'},
        -tag_type  => $data->{'tag_type'},
        -tag_info  => $data->{'tag_info'},
        -slice     => $slice,
    );

    my $list = $assembly_tag_list{$self} ||= [];
    push @$list, $at;
}

sub build_AssemblyType {
    my($self, $data) = @_;
    $assembly_type{$self} = $data;
}

sub build_Exon {
    my ($self, $data) = @_;

    my $slice = $self->get_ChromosomeSlice;

    my $exon = Bio::Vega::Exon->new(
        -start     => $data->{'start'},
        -end       => $data->{'end'},
        -strand    => $data->{'strand'},
        -stable_id => $data->{'stable_id'},
        -slice     => $slice,
    );
    my $frame=$data->{'frame'};
    if (defined($frame)) {
        $exon->phase((3-$frame)%3);
    }
    if (defined $exon->phase){
        $exon->end_phase(($exon->length + $exon->phase)%3);
    } else {
        $exon->phase(-1);
        $exon->end_phase(-1);
    }
    my $list = $exon_list{$self} ||= [];
    push @$list, $exon;
}

sub build_Transcript {
    my ($self, $data) = @_;

    my $exons = delete $exon_list{$self};
    my $slice = $self->get_ChromosomeSlice;

    my $ana = $logic_ana{$self}{'Otter'} ||= Bio::EnsEMBL::Analysis->new(-logic_name => 'Otter');

    my $transcript = Bio::Vega::Transcript->new(
        -stable_id => $data->{'stable_id'},
        -analysis  => $ana,
        -slice     => $slice,
    );

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
		##probably add a check to see if $end_Exon_Pos is set or not
		if ($start_Exon->strand == 1 && $start_Exon->start != $tran_start_pos) {
		  $start_Exon->end_phase(($start_Exon->length-$start_Exon_Pos+1)%3);
		} elsif ($start_Exon->strand == -1 && $start_Exon->end != $tran_start_pos) {
		  $start_Exon->end_phase(($start_Exon->length-$start_Exon_Pos+1)%3);
		}
		if ($end_Exon->length >= $end_Exon_Pos) {
		  $end_Exon->end_phase(-1);
		}
		$transcript->translation($translation);
	 }
  }
  elsif (defined $tran_start_pos || defined $tran_end_pos) {
	 die "ERROR: Only half of translation start/ end pair is defined\n";
  }

  # biotype and status from transcript class name
  my ($biotype, $status) = method2biotype_status($data->{'transcript_class'});
  $transcript->biotype($biotype);
  $transcript->status($status);

  my $author_name       = $data->{'author'};
  my $author_email      = $data->{'author_email'};
  my $transcript_author = $self->make_Author($author_name, $author_email);
  $transcript->transcript_author($transcript_author);


  ##transcript attributes
  my $transcript_attributes;
  my $mRNA_start_not_found = $data->{'mRNA_start_not_found'};
  if (defined $mRNA_start_not_found){
	 my $attrib=$self->make_Attribute('mRNA_start_NF','mRNA start not found','',$mRNA_start_not_found);
	 push @$transcript_attributes,$attrib;
  }
  my $mRNA_end_not_found = $data->{'mRNA_end_not_found'};
  if (defined $mRNA_end_not_found ){
	 my $attrib=$self->make_Attribute('mRNA_end_NF','mRNA end not found ','',$mRNA_end_not_found);
	 push @$transcript_attributes,$attrib;
  }
  my $cds_start_not_found = $data->{'cds_start_not_found'};
  if (defined $cds_start_not_found ){
	 my $attrib= $self->make_Attribute('cds_start_NF','cds start not found','',$cds_start_not_found);
	 push @$transcript_attributes,$attrib;
  }
  my $cds_end_not_found = $data->{'cds_end_not_found'};
  if (defined $cds_end_not_found ){
	 my $attrib= $self->make_Attribute('cds_end_NF','cds end not found','',$cds_end_not_found);
	 push @$transcript_attributes,$attrib;
  }

  if(my $remarks=$data->{'remark'}) {
      foreach my $rem (@$remarks){
        my $attrib;
        if($rem=~/Annotation_remark-\s+(.+)/) {
            $rem=$1;
            $attrib=$self->make_Attribute('hidden_remark','Hidden Remark','',$rem);
        } else {
            $attrib=$self->make_Attribute('remark','Remark','Annotation Remark',$rem);
        }
        push @$transcript_attributes,$attrib;
      }
  }

  if(my $transcript_name=$data->{'name'}) {
	 if ($seen_transcript_name{$self}{$transcript_name}) {
		die "more than one transcript has the name $transcript_name";
	 } else {
		$seen_transcript_name{$self}{$transcript_name} = 1;
	 }
	 my $attrib=$self->make_Attribute('name','Name','Alternative/long name',$transcript_name);
	 push @$transcript_attributes,$attrib;
  }

  ##add transcript attributes
  $transcript->add_Attributes(@$transcript_attributes);

  ##evidence
  my $evidence_l = delete $evidence_list{$self} || [];
  $transcript->evidence_list($evidence_l);

  my $list = $transcript_list{$self} ||= [];
  push @$list, $transcript;
}

sub translation_pos {
  my ($self,$loc,$exon) = @_;
  if ($loc <= $exon->end && $loc >= $exon->start) {
	 if ($exon->strand == 1) {
		return (($loc - $exon->start) + 1);
	 } else {
		return (($exon->end - $loc) + 1);
	 }
  } else {
	 return (undef);
  }
}

sub build_Locus {
	my ($self, $data) = @_;

	## version and is_current ??
	my $transcripts = delete $transcript_list{$self};
	## transcript author group has been temporarily set to 'anything' ??

	my $slice = $self->get_ChromosomeSlice;
	my $ana = $logic_ana{$self}{'Otter'} ||= Bio::EnsEMBL::Analysis->new(-logic_name => 'Otter');
	my $gene = Bio::Vega::Gene->new(
		-stable_id => $data->{'stable_id'},
		-slice => $slice,
		-description => $data->{'description'},
		-analysis => $ana,
		);


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

	$gene->source($source);
	$gene->biotype($biotype);
	$gene->status($status);

	##gene author
	my ($gene_author,$author_name,$author_email);
	$author_name  = $data->{'author'};
	$author_email = $data->{'author_email'};
	$gene_author  = $self->make_Author($author_name, $author_email, $source);

	$gene->gene_author($gene_author);

	##gene attributes name,synonym,remark
	my $gene_attributes=[];
	my $gene_name=$data->{'name'};
	if (defined $gene_name ) {
		if ($seen_gene_name{$self}{$gene_name}) {
			die "more than one gene has the name $gene_name";
		} else {
			$seen_gene_name{$self}{$gene_name} = 1;
		}
		my $name_attrib=$self->make_Attribute('name','Name','Alternative/long name',$gene_name);
		push @$gene_attributes,$name_attrib;
	}
	my $gene_synonym=$data->{'synonym'};
	if (defined $gene_synonym){
		foreach my $a (@$gene_synonym) {
			my $syn_attrib=$self->make_Attribute('synonym','Synonym','',$a);
			push @$gene_attributes,$syn_attrib;
		}
	}

    if(my $remarks=$data->{'remark'}) {
        foreach my $rem (@$remarks){
            my $attrib;
            if($rem=~/Annotation_remark-\s+(.+)/) {
                $rem=$1;
                $attrib=$self->make_Attribute('hidden_remark','Hidden Remark','',$rem);
            } else {
                $attrib=$self->make_Attribute('remark','Remark','Annotation Remark',$rem);
            }
            push @$gene_attributes,$attrib;
        }
    }

	##share exons among transcripts of this gene
	foreach my $tran (@$transcripts) {
		$gene->add_Transcript($tran);
	}
	$gene->prune_Exons;
	##add all gene attributes
	$gene->add_Attributes(@$gene_attributes);
	##truncated flag
	my $truncated=$data->{'truncated'};
	if (defined $truncated) {
		$gene->truncated_flag($truncated);
	}

	#convert coordinates from chromosomal coordinates to slice coordinates

	my $slice_offset = $slice->start - 1;

	foreach my $exon (@{$gene->get_all_Exons}) {
		$exon->start($exon->start - $slice_offset);
		$exon->end(  $exon->end   - $slice_offset);
	}

	foreach my $transcript (@$transcripts){
		$transcript->start($transcript->start - $slice_offset);
		$transcript->end(  $transcript->end   - $slice_offset);
	}

	$gene->start($gene->start - $slice_offset);
	$gene->end(  $gene->end   - $slice_offset);

	my $list = $gene_list{$self} ||= [];
	push @$list, $gene;
}

sub do_nothing {
}

sub get_AssemblyType {
  my $self=shift;
  return $assembly_type{$self};
}

sub set_ChromosomeSlice {
  my ($self,$slice)=@_;
  $slice{$self}{'chr'}=$slice;
}

sub get_ChromosomeSlice {
  my $self=shift;
  return $slice{$self}{'chr'};
}

sub get_AssemblySlices {
  my $self=shift;
  return $slice{$self};
}

sub get_CloneSlices {
  my $self=shift;
  my $clones=[];
  foreach my $piece ($slice{$self}{'cln_ctg'}){
	 my $cln_slice=$piece->[0];
	 push @$clones,$cln_slice;
  }
  return $clones;
}

sub get_Genes {
  my $self=shift;
  return $gene_list{$self} || [];
}

sub get_AssemblyTags {
  my $self=shift;
  return $assembly_tag_list{$self} || [];
}

sub get_SimpleFeatures {
  my $self=shift;
  return $feature_list{$self} || [];
}

sub get_SequenceSet_AssemblyType {
  my $self=shift;
  return;
}


##make Otter objects methods

sub make_Attribute{
  my ($self,$code,$name,$description,$value) = @_;
  my $attrib = Bio::EnsEMBL::Attribute->new
	 (
	  -CODE => $code,
	  -NAME => $name,
	  -DESCRIPTION => $description,
	  -VALUE => $value
	 );
  return $attrib;
}

sub make_ContigInfo{
  my ($self,$ctg_slice,$ctg_author,$author,$attributes) = @_;
  if (defined $ctg_author->name && ! defined $ctg_author->email){
	 die "contig author name set but not email";
  }
  if (!defined $ctg_author->name && defined $ctg_author->email){
	 die "contig author name not set but email is set";
  }
  unless ($ctg_author->name && $ctg_author->email) {
	 $ctg_author->name($author->name);
	 $ctg_author->email($author->email);
	 warn "contig author not set and setting author to client author\n";
  }
  my $ctg_info = Bio::Vega::ContigInfo->new (
	  -slice => $ctg_slice,
	  -author => $ctg_author,
	  -attributes => $attributes
  );
  return $ctg_info;
}

sub make_CoordSystem {
    my ($self,$name) = @_;

    if (!defined $name) {
        die "coord system name is a must to create a coordinate system object\n";
    }

    unless ($coord_system{$self}{$name}) {

        my $init_version = $name eq 'chromosome' ? $self->init_CoordSystem_Version : '';

        my ($rank, $seq_level, $default, $version) = @{ {
            'chromosome'  => {
                #'vega'  => [ 1, 0, 1, 'Vega' ],
                'otter' => [ 2, 0, 0, 'Otter'],
            },
            #'supercontig' => {
            #    '' =>      [ 3, 0, 1, undef],
            #},
            'clone'       => {
                '' =>      [ 4, 0, 1, undef],
            },
            'contig'      => {
                '' =>      [ 5, 1, 1, undef],
            },
        } -> {$name}{$init_version} };
     
        $coord_system{$self}{$name} =  Bio::EnsEMBL::CoordSystem->new(
            -name           => $name,
            -rank           => $rank,
            -sequence_level => $seq_level,
            -default        => $default,
            -version        => $version,
        );
    }
    return $coord_system{$self}{$name};
}

sub make_Slice {
    my ($self,$seq_region_name,$start,$end,$length,$strand,$coord_system)=@_;

    my $slice = Bio::EnsEMBL::Slice->new (
        -seq_region_name   => $seq_region_name,
        -start             => $start,
        -end               => $end,
        -seq_region_length => $length,
        -strand            => $strand,
        -coord_system      => $coord_system,
    );
    return $slice;
}

sub make_Author {
    my ($self, $name, $email, $group_name) = @_;

    $name  ||= 'nobody';
    $email ||= $name;

    my $author;
    unless ($author = $author_cache{$self}{$email}) {
        # print STDERR "make_Author called: name=[$name], email=[$email], group_name=[$group_name]\n";
        # for other groups, current strategy is to patch the database by hand
        my $group_email;
        if ($email =~ /[^\w\-]/) {
            $group_name  ||= 'havana';
            $group_email   = 'vega@sanger.ac.uk';
        }
        my $group = Bio::Vega::AuthorGroup->new (
            -name   => $group_name,
            -email  => $group_email,
        );

        $author = Bio::Vega::Author->new (
            -name   => $name,
            -email  => $email,
            -group  => $group,
        );
        $author_cache{$self}{$email} = $author;
    }
    return $author;
}

1;

__END__

=head1 NAME - Bio::Vega::Transform::Otter

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

