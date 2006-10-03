#!/usr/local/bin/perl -w

### transfer_MHC_annotation
### Author ck1@sanger.ac.uk

use strict;
use Bio::Otter::Lace::Defaults;
use Bio::Otter::AnnotatedGene;
use Bio::Otter::DBSQL::AnnotatedGeneAdaptor;
use Bio::Otter::Converter;
use Bio::EnsEMBL::Translation;

my ($dataset, $file_loc, $chrom_digit, $test);

Bio::Otter::Lace::Defaults::do_getopt('ds|dataset=s' => \$dataset, # eg, human or mouse or zebrafish
									  'dir=s'        => \$file_loc,
									  'chrom=i'      => \$chrom_digit,
									  'test'         => \$test
									 );
# $client talks to otter HTTP server
my $client   = Bio::Otter::Lace::Defaults::make_Client();          # Bio::Otter::Lace::Client
my $dset     = $client->get_DataSet_by_name($dataset);	           # Bio::Otter::Lace::DataSet
my $otter_db = $dset->get_cached_DBAdaptor;                        # Bio::EnsEMBL::Containerr
my $sliceAd  = $otter_db->get_SliceAdaptor;
my $geneAd   = $otter_db->get_GeneAdaptor;	                       # Bio::Otter::AnnotatedGeneAdaptor

my $MHC_geneObj;

my ($MHC_geneSIDs, $MHC_exonSID_start_end, $exonSID_MHC_transSID, $MHC_success_Gene, $MHC_failed_trans) =
parse_transfer($file_loc);

# copy PGF geneobj annotations to other haplotypes
copy_annotations();

# output results
output_gene_to_XML($MHC_geneObj);


#------------------------------------------------
#              s u b r o u t i n e s
#------------------------------------------------

sub copy_annotations {

  foreach my $haplotype ( keys %{$MHC_exonSID_start_end} ) {

	# test
#	next if $haplotype ne "MHC_APD-02";# COX";
#	next if $haplotype ne "MCH_COX";

	warn "#MHC: [$haplotype]";
	
	my $PGF_slice = get_MHC_slice("MHC_PGF", $chrom_digit);
	my $pgf_gene_ids = $geneAd->list_current_dbIDs_for_Slice($PGF_slice);
	my $MHC_slice = get_MHC_slice($haplotype, $chrom_digit);

	foreach my $pgf_id ( @$pgf_gene_ids ){

	  my $pgf     = $geneAd->fetch_by_dbID($pgf_id);
	  my $geneSID = $pgf->stable_id;

	  # full gene transferred
	  if ( exists $MHC_success_Gene->{$haplotype}->{$geneSID} ) {
		copy_full_transfer($haplotype, $MHC_slice, $pgf, $geneSID);
	  }

	  # partial gene transfer
	  elsif ( exists $MHC_geneSIDs->{$haplotype}->{$geneSID} and !exists $MHC_success_Gene->{$haplotype}->{$geneSID} ){
		copy_partial_transfer($haplotype, $MHC_slice, $pgf, $geneSID);
	  }
	}
#	warn "$haplotype done";
  }
}

sub copy_full_transfer {
  my ($haplotype, $MHC_slice, $pgf, $geneSID) = @_;

# need to change genename so there is no duplacate within same sequence_set
  my $geneName = $pgf->gene_info->name->name;
  $geneName .= "-2";
  my $gn =$pgf->gene_info->name;
  $gn->name($geneName);

  foreach my $trans ( @{$pgf->get_all_Transcripts} ) {

  	# remark for the script-modified transcript
	my $remark = "Annotation_remark- automatic annotation transfer from PGF haplotype";
	$trans->transcript_info->remark( new Bio::Otter::TranscriptRemark(-remark => $remark) );
  }

  foreach my $exon ( @{$pgf->get_all_Exons} ) {

	my $exonSID = $exon->stable_id;
	
	my $transSID = $exonSID_MHC_transSID->{$exonSID}->{$haplotype}->{transSID};
	#warn "#[ PGF ", $exonSID, " ", $exon->start, " ", $exon->end, "]";

	# now change coords to the mapped ones
	eval {
	  $exon->start($MHC_exonSID_start_end->{$haplotype}->{$exonSID}->{start});
	  $exon->end  ($MHC_exonSID_start_end->{$haplotype}->{$exonSID}->{end});
	};
	die($@) if $@;

	# map $exon coords to corresponding MHC slice
	$exon->contig($MHC_slice);
  }

  # test
  if ( $test ){
	foreach my $exon ( @{$pgf->get_all_Exons} ) {
	  my $exonSID = $exon->stable_id;
	  my $transSID = $exonSID_MHC_transSID->{$exonSID}->{$haplotype}->{transSID};
		
	  warn "#[TEST] $haplotype => ", $exon->stable_id, " => ", $exon->start, " => ", $exon->end, " => $transSID\n";
	}
	warn "\n";
  }

  # can't do it here otherwise get "MSG: Could not find start or end exon in transcript" error
  #$pgf = deidentify($pgf);
  push(@{$MHC_geneObj->{$haplotype}}, $pgf);
}

sub copy_partial_transfer {

  my ($haplotype, $MHC_slice, $pgf, $geneSID) = @_;

  my $new_gene = Bio::Otter::AnnotatedGene->new();

  foreach my $k ( keys %$pgf ){
	next if $k eq "_transcript_array";
	$new_gene->{$k} = $pgf->{$k};
  }

  # need to change genename so there is no duplacate within same sequence_set
  my $geneName = $new_gene->gene_info->name->name;
  $geneName .= "-2";
  my $gn =$new_gene->gene_info->name;
  $gn->name($geneName);

  foreach my $trans ( @{$pgf->get_all_Transcripts} ) {
	my $transSID = $trans->transcript_info->transcript_stable_id;

	# remark for the script-modified transcript
	my $remark = "Annotation_remark- automatic annotation transfer from PGF haplotype";
	$trans->transcript_info->remark( new Bio::Otter::TranscriptRemark(-remark => $remark) );

	# pick successful trans
	unless ( exists $MHC_failed_trans->{$haplotype}->{$transSID} ) {
	  $new_gene->add_Transcript($trans);

	  # now change exon coords
	  foreach my $exon ( @{$trans->get_all_Exons} ) {

		my $exonSID = $exon->stable_id;
		#warn "#[ PGF ", $transSID, " ", $exonSID, " ", $exon->start, " ", $exon->end, "]";

		eval {
		  $exon->start($MHC_exonSID_start_end->{$haplotype}->{$exonSID}->{start});
		  $exon->end  ($MHC_exonSID_start_end->{$haplotype}->{$exonSID}->{end});
		};
		die($@) if $@;

		# map $exon coords to corresponding MHC slice
		$exon->contig($MHC_slice);
	  }
	}			
  }
  # test
  if ($test ){
	foreach my $exon ( @{$new_gene->get_all_Exons} ) {
	  my $exonSID = $exon->stable_id;
	  my $transSID = $exonSID_MHC_transSID->{$exonSID}->{$haplotype}->{transSID};

	  warn "#[P-TEST] $haplotype => ", $exon->stable_id, " => ", $exon->start, " => ", $exon->end, " => $transSID\n";
	}
	warn "\n";
  }

  # can't do it here otherwise get "MSG: Could not find start or end exon in transcript" error
  #$pgf = deidentify($pgf);

  push(@{$MHC_geneObj->{$haplotype}}, $new_gene);
}

sub deidentify {

  my $gene = shift;
  my $time = time;

  $gene->stable_id(undef);
  $gene->created($time);
  $gene->version(1);

  foreach my $trans ( @{$gene->get_all_Transcripts} ) {
	
	$trans->stable_id(undef);
	$trans->created($time);
	$trans->version(1);
	
	# undef protein stable ID
	if ( $trans->translation ) {
	  my $translation =  $trans->translation;
	  $translation->dbID(undef);
	  $translation->stable_id(undef);
	  $translation->version(1)
	}

	# remark for the script-modified transcript $t
	my $remark = "Annotation_remark- automatic annotation transfer from PGF haplotype";
	$trans->transcript_info->remark( new Bio::Otter::TranscriptRemark(-remark => $remark) );

	foreach my $exon ( @{$trans->get_all_Exons} ){
	  $exon->dbID(undef);
	  $exon->stable_id(undef);
	  $exon->created($time);
	  $exon->version(1);
	}
  }
  return $gene;
}

sub output_gene_to_XML {

  my $MHC_geneObj = shift;

  foreach my $haplotype ( keys %$MHC_geneObj ){

	warn $haplotype;
	my $file = $haplotype."_xml.".$$;
	open(my $fh, ">$file") or die;

	my $slice = get_MHC_slice($haplotype, 6);

	my $xmlstr = "";
	$xmlstr .= "<otter>\n";
	$xmlstr .= "<sequence_set>\n";
	my $chr      = $slice->chr_name;
	my $chrstart = $slice->chr_start;
	my $chrend   = $slice->chr_end;
	my $path     = $slice->get_tiling_path;

	$xmlstr .= Bio::Otter::Converter::path_to_XML($chr, $chrstart, $chrend, $haplotype, $path);
	
	foreach my $g (@{$MHC_geneObj->{$haplotype}} ){
	  if ($g->type ne 'obsolete') {
		$xmlstr .= $g->toXMLString . "\n";
	  }
    }

    $xmlstr .= "</sequence_set>\n";
    $xmlstr .= "</otter>\n";
	
	print $fh $xmlstr;
  }
}

sub parse_transfer {
  my ($dir) = shift;

  my $MHC_geneSIDs;
  my $MHC_exonSID_start_end;
  my $exonSID_MHC_transSID;
  my $MHC_success_Gene;
  my $MHC_failed_trans;

  my $atype = {
			   MHC_APD  => "MHC_APD-02",
			   MHC_COX  => "MHC_COX",
			   MHC_DBB  => "MHC_DBB-02",
			   MHC_MANN => "MHC_MANN-02",
			   MHC_MCF  => "MHC_MCF-02",
			   MHC_QBL  => "MHC_QBL-03",
			   MHC_SSTO => "MHC_SSTO-03"
		  };

  foreach my $file ( glob("$dir/*.genes") ){

	open( my $fh, "$file") or die $!;
	while(<$fh>){

	  my @cols = split(/\s+/, $_);
	  my $haplotype  = $atype->{$cols[0]};

	  #MHC_MANN        gene    OTTHUMG00000031253      protein_coding  KNOWN
	  if ( /^MHC_.+\s+gene/ ){
		my $geneSID    = $cols[2];
		$MHC_geneSIDs->{$haplotype}->{$geneSID} = 1;
	  }

	  #MHC_APD exon    OTTHUME00000337188      121384  121584  1       -1      -1
	  if ( /^MHC_.+\s+exon\s+/ ){
		my $exonSID    = $cols[2];
		my $exon_start = $cols[3];
		my $exon_end   = $cols[4];

		$MHC_exonSID_start_end->{$haplotype}->{$exonSID}->{start} = $exon_start;
		$MHC_exonSID_start_end->{$haplotype}->{$exonSID}->{end} = $exon_end;
		# print "$haplotype $exonSID $exon_start $exon_end\n";
	  }

	  # #MHC_APD exon_transcript OTTHUME00000336610      OTTHUMT00000192604
	  elsif ( /^MHC_.+\s+exon_transcript\s+/ ){
		my $exonSID   = $cols[2];
		my $transSID  = $cols[3];
		$exonSID_MHC_transSID->{$exonSID}->{$haplotype}->{transSID} = $transSID;
	  }
	}
  }

  # exclude genes with success transfer
  foreach my $file ( glob("$dir/*.log") ){

	$file =~ /.+(MHC_.+)\.log/;
	my $haplotype = $atype->{$1};

	open( my $fh, "$file") or die $!;
	while(<$fh>){

	  #Summary for OTTHUMG00000031125 : 3 out of 4 transcripts transferred
	  if ( $_ =~ /^Summary for (.+) : (\d+) out of (\d+) transcripts transferred/ ){
		if ( $2 == $3 ){
		  $MHC_success_Gene->{$haplotype}->{$1} = 1;
		}
	  }
	  #OTTHUMT00000276173 Coding 32831853 32839287 did not transfer cleanly:
	  if ( /(OTTHUMT\d+).+did not transfer cleanly/ ){
		$MHC_failed_trans->{$haplotype}->{$1} = 1;
	  }
	}
  }

  return $MHC_geneSIDs, $MHC_exonSID_start_end, $exonSID_MHC_transSID, $MHC_success_Gene, $MHC_failed_trans;
}

sub get_MHC_slice {
  my ($atype, $chrom_digit) = @_;
  $otter_db->assembly_type($atype);
  return my $MHC_slice = $sliceAd->fetch_by_chr_name($chrom_digit);
}




__END__


