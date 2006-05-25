
### Bio::Vega::Transform::Otter

package Bio::Vega::Transform::Otter;

use strict;
use Carp;
use Bio::EnsEMBL::Exon;
use Bio::EnsEMBL::Transcript;
use Bio::EnsEMBL::Gene;
use Bio::EnsEMBL::SimpleFeature;
use Bio::EnsEMBL::Analysis;
use Bio::Vega::SequenceFragment;
use Bio::EnsEMBL::Slice;
use Bio::EnsEMBL::CoordSystem;

use base 'Bio::Vega::Transform';


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

sub build_SequenceFragment {
    my ($self, $data) = @_;
    my $fragment = Bio::Vega::SequenceFragment->new(
						 -id => $data->{'id'},
						 -chromosome => $data->{'chromosome'},
						 -assembly_start => $data->{'assembly_start'},
						 -assembly_end   => $data->{'assembly_end'},
						 -strand=> $data->{'fragment_ori'},
						 -offset=> $data->{'fragment_offset'},
						 -author=> $data->{'author'},
						 -remark=> $data->{'remark'},
						 -keyword=> $data->{'keyword'},
						 -accession=> $data->{'accession'},
						 -version=> $data->{'version'}
						 );

	 my $list = $fragment_list{$self} ||= [];
    push @$list, $fragment;																
}

sub build_Evidence {
    my ($self, $data) = @_;
}

sub build_Feature {
    my ($self, $data) = @_;
    my $ana = $logic_ana{$self}{$data->{'type'}} ||= Bio::EnsEMBL::Analysis->new(-logic_name => $data->{'type'});
	 my $slice = $self->make_ChromosomeSlice;
    my $feature = Bio::EnsEMBL::SimpleFeature->new(
        -start     => $data->{'start'},
        -end       => $data->{'end'},
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
	 my $slice = $self->make_ChromosomeSlice;
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
	 my $slice = $self->make_ChromosomeSlice;
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

sub make_ChromosomeSlice {
  my $self = shift;
  unless ($slice{$self}{'chr'}) {
	 my $fragment_list = $fragment_list{$self};
	 my $chrname  = undef;
	 my $chrstart = undef;
	 my $chrend   = undef;
	 if ( defined $fragment_list && scalar(@$fragment_list)) {
		foreach my $frag_data (@$fragment_list) {
		  if ($chrname and $chrname ne $frag_data->{chromosome}) {
			 die " Chromosome names are different - can't make slice [$chrname]["
				. $frag_data->{chromosome} . "]\n";
		  } else {
			 $chrname = $frag_data->{chromosome};
		  }
		  if (!defined($chrstart) or $frag_data->{assembly_start} < $chrstart) {
			 $chrstart = $frag_data->{assembly_start};
		  }
		  if (!defined($chrend) or $frag_data->{assembly_end} > $chrend) {
			 $chrend = $frag_data->{assembly_end};
		  }
		  unless ($chrname and $chrstart and $chrend) {
			 die "XML does not contain information needed to create slice:\n",
				"chr name='$chrname'  chr start='$chrstart'  chr end='$chrend'";
		  }
		}
	 }
	 else {
		print STDERR "No sufficient sequence fragment data for building a chromosome slice";
	 }
	 my $chr_coord_system=$self->make_CoordSystem('chromosome');
	 #confirm start,length settings
	 my $slice = make_Slice($self,$chrname,1,$chrend,$chrend,1,$chr_coord_system);
	 $slice{$self}{'chr'} ||= $slice;
	 return $slice{$self}{'chr'};
  }
}

sub make_Assembly {
  my $self = shift;
  my $cln_ctg_list = $segment{$self}{'cln_ctg'} ||= [];
  my $chr_ctg_list = $segment{$self}{'chr_ctg'} ||= [];
  unless (scalar(@$cln_ctg_list) && scalar(@$chr_ctg_list) ){
	 my $chr_slice =$self->make_ChromosomeSlice;
	 my $chr_name = $chr_slice->seq_region_name();
	 my $fragment_list = $fragment_list{$self};
	 if ( defined $fragment_list && scalar(@$fragment_list)) {
		my $cln_coord_system=$self->make_CoordSystem('clone');
		my $ctg_coord_system=$self->make_CoordSystem('contig');
		my $chr_coord_system = $self->make_CoordSystem('chromosome');
		foreach my $frag_data (@$fragment_list) {
		  ##make clone - contig slice
		  my $offset = $frag_data->{offset};
		  my $start  = $frag_data->{assembly_start};
		  my $end    = $frag_data->{assembly_end};
		  my $strand = $frag_data->{strand};
		  my $cmp_start = $offset;
		  my $cmp_end = $offset + $end - $start;
		  my $ctg_id=$frag_data->{id};
		  my $cln_length;
		  if ($ctg_id =~ /\S+\.\d+\.\d+\.(\d+)/){
			 $cln_length=$1;
		  }
		  if (!defined($start || $end || $strand || $offset || $ctg_id) ) {
			 die "ERROR: Either start:$start or end:$end or strand:$strand 
             or offset:$offset or contig_id:$ctg_id not defined in the xml file\n";
		  }
		  my $accession = $frag_data->{accession};
		  my $version = $frag_data->{version};
		  my $cln_name = $accession.$version;
		  my $cln_slice = make_Slice($self,$cln_name,1,$cln_length,$cln_length,1,$cln_coord_system);
		  my $ctg_slice = make_Slice($self,$ctg_id,1,$cln_length,$cln_length,1,$ctg_coord_system);
		  my $cln_ctg_piece=[$cln_slice->start(),$cln_slice->end(),$ctg_slice];
		  bless($cln_ctg_piece,"Bio::EnsEMBL::ProjectionSegment");
		  push @$cln_ctg_list,$cln_ctg_piece;
		  ##make chromosome - contig slice
		  my $chr_asm_slice = make_Slice($self,$chr_name,$start,$end,$end,$strand,$chr_coord_system);
		  my $ctg_cmp_slice = make_Slice($self,$ctg_id,$cmp_start,$cmp_end,$cmp_end,$strand,$ctg_coord_system);
		  my $chr_ctg_piece = [$chr_asm_slice->start(),$chr_asm_slice->end(),$ctg_cmp_slice];
		  bless($chr_ctg_piece,"Bio::EnsEMBL::ProjectionSegment");
		  push @$chr_ctg_list,$chr_ctg_piece;
		}
	 }
	 else {
		print STDERR "No sufficient sequence fragment data for building a Slice";
	 }
  }
  return $segment{$self};
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

1;

__END__

=head1 NAME - Bio::Vega::Transform::Otter

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

