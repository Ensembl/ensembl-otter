#!/usr/local/bin/perl -w

### transfer_MHC_annotation
### Author ck1@sanger.ac.uk

use strict;
use Bio::Otter::Lace::Defaults;
use Bio::Otter::AnnotatedGene;
use Bio::Otter::DBSQL::AnnotatedGeneAdaptor;

my ($dataset, $file_loc, $chrom_digit);

Bio::Otter::Lace::Defaults::do_getopt('ds|dataset=s' => \$dataset, # eg, human or mouse or zebrafish
									  'dir=s'        => \$file_loc,
									  'chrom=i'      => \$chrom_digit,
									 );

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
  }
}

sub copy_full_transfer {
  my ($haplotype, $MHC_slice, $pgf, $geneSID) = @_;

  foreach my $exon ( @{$pgf->get_all_Exons} ) {

	my $exonSID = $exon->stable_id;
	
	# now change coords to the mapped ones
	
	my $transSID = $exonSID_MHC_transSID->{$exonSID}->{$haplotype}->{transSID};
	warn "#[ PGF ", $exonSID, " ", $exon->start, " ", $exon->end, "]";

	eval {
	  $exon->start($MHC_exonSID_start_end->{$haplotype}->{$exonSID}->{start});
	  $exon->end  ($MHC_exonSID_start_end->{$haplotype}->{$exonSID}->{end});
	};
	die($@) if $@;

	# map $exon coords to corresponding MHC slice
	$exon->contig($MHC_slice);
  }

  # test
  foreach my $exon ( @{$pgf->get_all_Exons} ) {
	my $exonSID = $exon->stable_id;
	my $transSID = $exonSID_MHC_transSID->{$exonSID}->{$haplotype}->{transSID};
		
	warn "#[TEST] $haplotype => ", $exon->stable_id, " => ", $exon->start, " => ", $exon->end, " => $transSID\n";
  }
  warn "\n";
  push(@{$MHC_geneObj->{$haplotype}}, $pgf);
#  print $pgf->toXMLString;
}


sub copy_partial_transfer {

  my ($haplotype, $MHC_slice, $pgf, $geneSID) = @_;

  my $new_gene = Bio::Otter::AnnotatedGene->new();

  foreach my $trans ( @{$pgf->get_all_Transcripts} ) {
	my $transSID = $trans->transcript_info->transcript_stable_id;

	# pick successful trans
	unless ( exists $MHC_failed_trans->{$haplotype}->{$transSID} ) {
	  $new_gene->add_Transcript($trans);

	  # now change exon coords
	  foreach my $exon ( @{$trans->get_all_Exons} ) {

		my $exonSID = $exon->stable_id;
		warn "#[ PGF ", $exonSID, " ", $exon->start, " ", $exon->end, "]";

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
  foreach my $exon ( @{$new_gene->get_all_Exons} ) {
	my $exonSID = $exon->stable_id;
	my $transSID = $exonSID_MHC_transSID->{$exonSID}->{$haplotype}->{transSID};
		
	warn "#[P-TEST] $haplotype => ", $exon->stable_id, " => ", $exon->start, " => ", $exon->end, " => $transSID\n";
  }
  warn "\n";
  push(@{$MHC_geneObj->{$haplotype}}, $pgf);
  #print $new_gene->toXMLString;
}

sub output_gene_to_XML {

  my $MHC_geneObj = shift;

  foreach my $haplotype ( keys %$MHC_geneObj ){

	my $file = $haplotype."_xml.".$$;
	open(my $fh, ">$file") or die;
	foreach my $g (@{$MHC_geneObj->{$haplotype}} ){
	   print $fh $g->toXMLString;
	}
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
	  if ( /^MHC_MANN\s+gene/ ){
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
	  if ( $_ =~ /Summary for (.+) : (\d+) out of (\d+) transcripts transferred/ ){
		if ( $2 == $3 ){
		  $MHC_success_Gene->{$haplotype}->{$1} = 1;
		}
	  }
	  elsif ( /(OTTHUMT\d+).+did not transfer cleanly/ ){
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


