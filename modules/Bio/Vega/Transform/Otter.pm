
### Bio::Vega::Transform::Otter

package Bio::Vega::Transform::Otter;

use strict;
use Carp;
use Bio::EnsEMBL::Exon;
use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::Gene;
use Bio::EnsEMBL::SimpleFeature;
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::Slice;
use Bio::EnsEMBL::CoordSystem;
use Bio::EnsEMBL::Pipeline::SeqFetcher::Finished_Pfetch;
use base 'Bio::Vega::Transform';
use Bio::EnsEMBL::Attribute;
use Bio::Vega::Author;
use Bio::Vega::AuthorGroup;
use Bio::Vega::ContigInfo;
use Data::Dumper;   # For debugging
# This misses the "$VAR1 = " bit out from the Dumper() output
$Data::Dumper::Terse = 1;

my (
    %exon_list,
    %gene_list,
    %transcript_list,
    %feature_list,
	 %logic_ana,
	 %fragment_list,
	 %coord_system,
	 %slice,
	 %segment,
    );


sub DESTROY {
    my ($self) = @_;

    delete $exon_list{$self};
    delete $gene_list{$self};
    delete $transcript_list{$self};
	 delete $feature_list{$self};
	 delete $logic_ana{$self};
	 delete $fragment_list{$self};
    delete $coord_system{$self};
	 delete $slice{$self};
	 delete $segment{$self};
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
			sequence_fragment   => 'build_Fragment',
			evidence            => 'build_Evidence',
			feature             => 'build_Feature',
			assembly_tag        => 'build_AssemblyTag',
			sequence_fragment   => 'build_SequenceFragment',
			# We don't currently do anything on encountering
			# these end tags:
			sequence_set        => 'report_set_end',
			exon_set            => 'report_set_end',
			evidence_set        => 'report_set_end',
			feature_set   => 'report_set_end',
			otter         => 'report_set_end',
        }
								  );
    $self->set_multi_value_tags(
		  [
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
}

sub init_CoordSystem_Version {
  my ($self,$value)=@_;
  $coord_system{$self}{'version'} ||= $value;
  return $coord_system{$self}{'version'};
}

## parser builder methods to build otter objects

sub build_SequenceFragment {

    my ($self, $data) = @_;

	 my $cln_coord_system=$self->make_CoordSystem('clone');
	 my $ctg_coord_system=$self->make_CoordSystem('contig');
	 my $chr_coord_system=$self->make_CoordSystem('chromosome');
	 my $chrname=$data->{'chromosome'};
	 my $offset = $data->{'fragment_offset'};
	 my $start  = $data->{'assembly_start'};
	 my $end    = $data->{'assembly_end'};
	 my $strand = $data->{'fragment_ori'};
	 my $chrslice=$self->get_ChromosomeSlice;
	 unless ($chrslice) {
		$chrslice = make_Slice($self,$chrname,$start,$end,$end,1,$chr_coord_system);
		 $slice{$self}{'chr'} ||= $chrslice;
	 }
	 else {
		$chrslice=$slice{$self}{'chr'};
		my $slice_name=$chrslice->seq_region_name();
		if ( $chrname ne $slice_name) {
		  die " Chromosome names are different - can't make slice [$chrname][$slice_name]\n";
		}
		my $slice_start=$chrslice->start();
		if ( $start < $slice_start ) {
		  $slice_start=$start;
		}
		my $slice_end=$chrslice->end();
		if ( $end > $slice_end ) {
		  $slice_end=$end;
		}
		unless ($chrname and $start and $end and $offset and $strand) {
		  die "XML does not contain information needed to create slice:\nchr name='$chrname'  chr start='$start'  chr end='$end' offset='$offset' strand = '$strand'";
		}
		my $new_chr_slice=make_Slice($self,$chrname,$slice_start,$slice_end,$slice_end,1,$chr_coord_system);
		$slice{$self}{'chr'}=$new_chr_slice;
	 }

	 my $cmp_start = $offset;
	 my $cmp_end = $offset + $end - $start;
	 my $ctg_id=$data->{'id'};
	 my $cln_length;
	 if ($ctg_id =~ /\S+\.\d+\.\d+\.(\d+)/){
		$cln_length=$1;
	 }
	 if (!defined($start || $end || $strand || $offset || $ctg_id) ) {
		die "ERROR: Either start:$start or end:$end or strand:$strand or offset:$offset or contig_id:$ctg_id not defined in the xml file\n";
	 }
	 my $accession = $data->{'accession'};
	 my $version = $data->{'version'};
	 my $cln_name = "$accession".".$version";
	 ##make clone - contig slice
	 my $cln_slice = $self->make_Slice($cln_name,1,$cln_length,$cln_length,$strand,$cln_coord_system);
	 my $ctg_slice = $self->make_Slice($ctg_id,1,$cln_length,$cln_length,$strand,$ctg_coord_system);
	 ## make clone-info attributes from remark and keyword
	 my $cln_attrib;
	 my $cln_attrib_list=[];
	 my $remarks=$data->{'remark'};
	 foreach my $rem (@$remarks){
		if ($rem =~ /EMBL_dump_info.DE_line-\s+(.+)/) {
		  $cln_attrib=$self->make_Attribute('description','EMBL Header Description','',$1);
		}
		elsif ($rem =~ /Annotation_remark-\s+(.+)/) {
		  $rem=$1;
		  if ($rem =~ /annotated/){
			 $rem=$1;
			 $cln_attrib=$self->make_Attribute('annotated','Clone Annotation Status','','T');
		  }
		  else {
			 $cln_attrib=$self->make_Attribute('hidden_remark','Hidden Remark','',$rem);
		  }
		}
		else {
		  $cln_attrib=$self->make_Attribute('visible_remark','Visible Remark','',$rem);
		}
		push @$cln_attrib_list,$cln_attrib;
	 }
	 my $keywords=$data->{'keyword'};
	 foreach my $key (@$keywords) {
		$cln_attrib=$self->make_Attribute('keyword','Clone Keyword','',$key);
		push @$cln_attrib_list,$cln_attrib;
	 }
	 my $cln_author=$self->make_Author($data->{'author'},$data->{'author_email'},'havana');
	 my $cln_ctg_piece=[$cln_slice,$ctg_slice];
	 my $cln_ctg_list = $slice{$self}{'cln_ctg'} ||= [];
	 push @$cln_ctg_list,$cln_ctg_piece;
	 ##make chromosome - contig slice
	 my $chr_asm_slice = $self->make_Slice($chrname,$start,$end,$end,$strand,$chr_coord_system);
	 my $ctg_cmp_slice = $self->make_Slice($ctg_id,$cmp_start,$cmp_end,$cmp_end,$strand,$ctg_coord_system);
	 my $chr_ctg_piece = [$chr_asm_slice,$ctg_cmp_slice,$cln_attrib_list,$cln_author];
	 my $chr_ctg_list = $slice{$self}{'chr_ctg'} ||= [];
	 push @$chr_ctg_list,$chr_ctg_piece;
}


sub build_Evidence {
    my ($self, $data) = @_;
}


sub build_Feature {
    my ($self, $data) = @_;
    my $ana = $logic_ana{$self}{$data->{'type'}} ||= Bio::EnsEMBL::Analysis->new(-logic_name => $data->{'type'});
	 my $slice = $self->get_ChromosomeSlice;
	 # convert xml coordinates which are in chromosomal coords - to feature coords
	 my $offset = 1 - $slice->start ;
	 my $feat_start = $data->{'start'} + $offset;
	 my $feat_end =  $data->{'end'}   + $offset;
    my $feature = Bio::EnsEMBL::SimpleFeature->new(
        -start     => $feat_start,
        -end       => $feat_end,
        -strand    => $data->{'strand'},
		  -analysis  => $ana,
	     -score     => $data->{'score'},
	     -display_label => $data->{'label'},
		  -slice => $slice,
    );
    my $list = $feature_list{$self} ||= [];
    push @$list, $feature;
}

sub build_AssemblyTag {
    my ($self, $data) = @_;
}

sub build_Exon {
    my ($self, $data) = @_;
	 my $slice = $self->get_ChromosomeSlice;
    my $exon = Bio::EnsEMBL::Exon->new(
        -start     => $data->{'start'},
        -end       => $data->{'end'},
        -strand    => $data->{'strand'},
        -stable_id => $data->{'stable_id'},
		  -slice     => $slice,
    );

    my $list = $exon_list{$self} ||= [];
    push @$list, $exon;
}

sub build_Transcript {
    my ($self, $data) = @_;

    my $exons = delete $exon_list{$self};

    my $transcript = Bio::EnsEMBL::Transcript->new(
        -stable_id => $data->{'stable_id'},
        );
	 foreach my $exon (@$exons) {
        $transcript->add_Exon($exon);
    }
    my $list = $transcript_list{$self} ||= [];
    push @$list, $transcript;
}

sub build_Locus {
    my ($self, $data) = @_;
    my $transcripts = delete $transcript_list{$self};
	 my $slice = $self->get_ChromosomeSlice;
    my $gene = Bio::EnsEMBL::Gene->new(
        -stable_id => $data->{'stable_id'},
		  -slice => $slice,
        );
    foreach my $tsct (@$transcripts) {
        $gene->add_Transcript($tsct);
    }

    my $list = $gene_list{$self} ||= [];
    push @$list, $gene;
}

sub report_set_end {
    my ($self) = @_;
    # Do nothing
}

###load parsed otter objects to otter database

sub LoadAssemblySlices {
  my ($self,$db)= @_;
  eval {
	 $db->begin_work();
	 my $dbc= $db->dbc();
	 my $sa=$db->get_SliceAdaptor();
	 my $slice=$self->get_AssemblySlices;
	 my $chr_slice=$slice->{'chr'};
	 my $new_slice=$self->get_SliceId($chr_slice,$db);
	 my $asm_seq_reg_id=$sa->get_seq_region_id($new_slice);
	 #die $asm_seq_reg_id;
	 my $chr_ctg = $slice->{'chr_ctg'};
	 ##insert all contigs
	 foreach my $piece (@$chr_ctg) {
		my $asm_slice = $piece->[0];
		my $cmp_slice = $piece->[1];
		my $new_slice=$self->get_SliceId($cmp_slice,$db);
		my $cmp_seq_reg_id=$sa->get_seq_region_id($new_slice);
		##insert chromosome-contig assembly
		$self->insert_Assembly($dbc,$asm_seq_reg_id,$cmp_seq_reg_id,$asm_slice->start,$asm_slice->end,$cmp_slice->start,$cmp_slice->end,$cmp_slice->strand);

		##insert contig_info and attributes
		my $ctg_attrib_list=$piece->[2];
		my $ctg_author=$piece->[3];
		my $ctg_info_id = $self->insert_ContigInfo_Attributes($db,$ctg_author,$new_slice,$ctg_attrib_list);

	 }

	 my $cln_ctg = $slice->{'cln_ctg'};
	 ##insert all clones
	 foreach my $piece (@$cln_ctg) {
		my $asm_slice = $piece->[0];
		my $cmp_slice = $piece->[1];
		my $new_slice=$self->get_SliceId($asm_slice,$db);
		my $asm_seq_reg_id=$sa->get_seq_region_id($new_slice);
		$new_slice=$self->get_SliceId($cmp_slice,$db);
		my $cmp_seq_reg_id=$sa->get_seq_region_id($new_slice);
		##insert clone-contig assembly
		$self->insert_Assembly($dbc,$asm_seq_reg_id,$cmp_seq_reg_id,$asm_slice->start,$asm_slice->end,$cmp_slice->start,$cmp_slice->end,$cmp_slice->strand);
	 }
  };
  if ($@) {
	 $db->rollback;
	 print STDERR "Error saving genes from file:".$@;
  }
  else {
	 $db->commit;
  }

}

sub insert_ContigInfo_Attributes {
  my ($self,$db,$ctg_author,$ctg_slice,$ctg_attrib_list)=@_;
  my $dbc= $db->dbc();
  my $ca=$db->get_ContigInfoAdaptor();
  my $contig_info=$self->make_ContigInfo($ctg_slice,$ctg_author,$ctg_attrib_list);
  $ca->store($contig_info);

}

sub  insert_Assembly {
  my($self,$dbc,$asm_seq_reg_id,$cmp_seq_reg_id,$asm_start,$asm_end,$cmp_start,$cmp_end,$cmp_strand) = @_;
  my $select_assembly=$dbc->prepare("select count(*) from assembly where asm_seq_region_id = ? and cmp_seq_region_id = ? and asm_start =? and asm_end = ? and cmp_start = ? and cmp_end = ? and ori = ?");
  $select_assembly->execute($asm_seq_reg_id,$cmp_seq_reg_id,$asm_start,$asm_end,$cmp_start,$cmp_end,$cmp_strand);
  my ($count) = $select_assembly->fetchrow;
  if ($count > 0) {
	 print STDERR "assembly already in table with asm_seq_reg_id :$asm_seq_reg_id, and so not loaded\n";
  }
  else {
	 my  $insert_assembly=$dbc->prepare("insert into assembly 
	  (asm_seq_region_id ,cmp_seq_region_id ,asm_start ,asm_end ,cmp_start ,cmp_end ,ori)
	  values  (?, ?,?,?,?,?,?)");
	 $insert_assembly->execute($asm_seq_reg_id,$cmp_seq_reg_id,$asm_start,$asm_end
									 ,$cmp_start,$cmp_end,$cmp_strand);
  }

}

##get instant variable values of instantiated object

sub get_SliceId {

  my ($self,$slice,$db)=@_;
  my $dbc= $db->dbc();
  my $sa=$db->get_SliceAdaptor();
  my $csa = $db->get_CoordSystemAdaptor();
  my ($seq_reg_id,$new_slice,$slice_cs,$cs);
  ## check if the contig is already stored in db
  $slice_cs=$slice->coord_system;
  eval{
	 $cs = $csa->fetch_by_name($slice_cs->name,$slice_cs->version,$slice_cs->rank);
  };
  if($@){
	 print STDERR "A coord_system matching the arguments does not exsist in the cord_system table, please ensure you have the right coord_system entry in the database:$@";
  }
  $new_slice = $sa->fetch_by_name($slice->name);
  if($new_slice){
	 warn "slice <".$slice->seq_region_name."> is already in the database\n";
	 $seq_reg_id = $sa->get_seq_region_id($new_slice);
  }
  else {
		##make a new slice with the coord_system of the database for contig
		$new_slice=$self->make_Slice($slice->seq_region_name,1,$slice->end,$slice->end,1,$cs);
		my $seq;
		my $seq_name=$slice->seq_region_name;
		if ($slice_cs->name eq 'contig') {
		  ##fetch sequence for contig
		  my ($acc_ver)=$seq_name =~ /^(.+\.\d+)\.\d+\.\d+$/;
		  my $seqobj = $self->pfetch_acc_ver($acc_ver);
		  $seq   = $seqobj->seq;
		  ##insert slice
		  $seq_reg_id = $sa->store($new_slice,\$seq);
		  ##assign new slice
		  $slice=$new_slice;
		}
		else {
		  ##insert slice
		  $seq_reg_id = $sa->store($new_slice);
		  ##assign new slice
		  $slice=$new_slice;
		  if ($slice_cs->name eq 'clone') {
			 ##make clone attributes
			 my @attrib;
			 my $aa = $db->get_AttributeAdaptor();
			 my ($acc,$sv)= $seq_name=~/^(.+)\.(\d+)$/;
			 push @attrib,$self->make_Attribute('htgs_phase','HTGS Phase','High Throughput Genome Sequencing Phase','3');
			 push @attrib,$self->make_Attribute('intl_clone_name','International Clone Name','',$seq_name);
			 push @attrib,$self->make_Attribute('embl_accession','EMBL Accession','',$acc);
			 push @attrib,$self->make_Attribute('embl_version','EMBL Version','',$sv);
			 ##store clone attributes
			 $aa->store_on_Slice($new_slice,\@attrib);
		  }
		}
	 }
  return $new_slice;
}

sub get_ChromosomeSlice {
  my $self=shift;
  return $slice{$self}{'chr'};
}

sub get_AssemblySlices {
  my $self=shift;
  return $slice{$self};
}

###fetch sequence

sub pfetch_acc_ver {
  my( $self,$acc_ver ) = @_;
  my $pfetch         ||= Bio::EnsEMBL::Pipeline::SeqFetcher::Finished_Pfetch->new;
  my $pfetch_archive ||= Bio::EnsEMBL::Pipeline::SeqFetcher::Finished_Pfetch->new(
							 -PFETCH_PORT => 23100,);
  my $seq = $pfetch->get_Seq_by_acc($acc_ver);
  unless ($seq) {
	 warn "Fetching '$acc_ver' from archive\n";
	 $seq = $pfetch_archive->get_Seq_by_acc($acc_ver);
  }
  unless ($seq) {
	 die "cannot fetch sequence\n";
  }
  return $seq;
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
    my ($self,$ctg_slice,$author,$attributes) = @_;

    my $ctg_info = Bio::Vega::ContigInfo->new
	(
	 -slice => $ctg_slice,
	 -author => $author,
	 -attributes => $attributes
	 );

    return $ctg_info;
}

sub make_CoordSystem {
  my ($self,$name) = @_;
  if (!defined $name) {
	 die "coord system name is a must to create a coordinate system object\n";
  }
  unless ($coord_system{$self}{$name}){
	 my $rank;
	 my $default=1;
	 my $seq_level=0;
	 my $version;
	 if ($name eq 'chromosome') {
		$version=$self->init_CoordSystem_Version;
		if ($version eq 'otter'){
		  $rank=2;
		  $default=0;
		}
		elsif ($version eq 'vega'){
		  $rank=1;
		}
	 }
	 if ($name eq 'contig'){
		$seq_level=1;
		$rank=5;
	 }
	 elsif ($name eq 'clone'){
		$rank=4;
	 }
	 elsif ($name eq 'supercontig'){
		$rank=3;
	 }
	 $coord_system{$self}{$name} =  Bio::EnsEMBL::CoordSystem->new(
										   -name    => $name,
										   -version => $version,
                                 -rank    => $rank,
                                 -default => $default,
                                 -sequence_level => $seq_level
								 		  );
  }
  return $coord_system{$self}{$name};
}

sub make_Slice {
  my ($self,$seq_region_name,$start,$end,$length,$strand,$coord_system)=@_;
  my $slice = Bio::EnsEMBL::Slice->new
		  (
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
  my ($self,$name,$email,$group_name)=@_;
  my $group = Bio::Vega::AuthorGroup->new
	 (
	  -name   => $group_name,
	 );

  my $author = Bio::Vega::Author->new
	 (
	  -name   => $name,
	  -email  => $email,
	  -group  => $group,
	 );

  return $author;
}

1;

__END__

=head1 NAME - Bio::Vega::Transform::Otter

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

