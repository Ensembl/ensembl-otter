#!/usr/local/bin/perl -w

use strict;
use Getopt::Long 'GetOptions';
use Bio::Otter::Lace::Defaults;
use DBI;
use Bio::EnsEMBL::SimpleFeature;
use Bio::EnsEMBL::AssemblyMapper;
use Bio::EnsEMBL::Analysis;
{

  my ($dataset, @sets, $vega_db, $eucommFile, $verbose);

  my $help = sub { exec('perldoc', $0) };

  Bio::Otter::Lace::Defaults::do_getopt('ds|dataset=s' => \$dataset,    # eg, human or mouse or zebrafish
										's|set=s@'     => \@sets,       # sequence set(s) to check
										'h|help'       => $help,
										'vegadb=s'     => \$vega_db,
										'eucomm=s'     => \$eucommFile,
										'verbose'      => \$verbose
									   ) or $help->();                  # plus default options
  $help->() unless ( $dataset );

  my $client      = Bio::Otter::Lace::Defaults::make_Client();	        # Bio::Otter::Lace::Client
  my $dset        = $client->get_DataSet_by_name($dataset);             # Bio::Otter::Lace::DataSet
  my $otter_db    = $dset->get_cached_DBAdaptor;                        # Bio::EnsEMBL::Containerr
  my $mapper_ad   = $otter_db->get_AssemblyMapperAdaptor();
  my $sf_ad       = $otter_db->get_SimpleFeatureAdaptor();
  my $rca         = $otter_db->get_RawContigAdaptor;
  my $vega        = connect_vega_db($vega_db);
  my $atype_feats = parse_and_verify_eucomm_data($eucommFile, $vega);

  my @simpleFeatures;

  foreach my $atype ( keys %$atype_feats ){

	print "Working on $atype\n";

	$otter_db->assembly_type($atype);

	foreach my $chr_name ( keys %{$atype_feats->{$atype}} ){

	  foreach my $feat (@{$atype_feats->{$atype}->{$chr_name}} ){

		my $feat_start = $feat->[0];
		my $feat_end   = $feat->[1];
		my $feat_lbl   = $feat->[2];
		my $strand     = 1; # default by Eucomm
		my $chr_start  = 1;
		my $chr_end    = $otter_db->get_ChromosomeAdaptor()->fetch_by_chr_name($chr_name)->length();

		# preparing coord mapper for whole chr of an assembly_type
		my $mapper     = $mapper_ad->fetch_by_type($atype);
		$mapper_ad->register_region($mapper, $atype, $chr_name, $chr_start, $chr_end);

		print "Feat_start: $feat_start, Feat_end: $feat_end, Label: $feat_lbl\n" if $verbose;

		# transforming chrom. coord to contig coord
		my @raw_coordlist = $mapper->map_coordinates_to_rawcontig( $chr_name, $feat_start, $feat_end, $strand );
		for my $coord (@raw_coordlist) {

		  # make simplefeature obj
		  print "mapped to: contig_id=".$coord->id().", start=".$coord->start().", end=".$coord->end().", strand=".$coord->strand().".\n" if $verbose;

		  my $analysis = new Bio::EnsEMBL::Analysis;

          $analysis->dbID(9);
          $analysis->logic_name("EUCOMM_AUTO");

		  my $sf = new Bio::EnsEMBL::SimpleFeature;
		  $sf->dbID($coord->id);
		  $sf->start($coord->start);
		  $sf->end($coord->end);
		  $sf->strand($coord->strand);
		  $sf->analysis($analysis);
		  $sf->display_label($feat_lbl);
		  $sf->score(1);

          # now attach a rawContig object to simplefeature
          my $contig = $rca->fetch_by_dbID($coord->id);
          $sf->attach_seq($contig);

		  push(@simpleFeatures, $sf);
		}
	  }
	}
  }

  # now store simple features
  foreach my $sf (@simpleFeatures ){
	$sf_ad->store($sf);
  }
}

sub parse_and_verify_eucomm_data {

  my ($eucommFile, $vega_db) = @_;

  open(EU, "<$eucommFile") or die $1;

  my $exonID_data = {};

  while ( <EU> ){

	# similarity      OTTMUSE00000020324      D1R     D1R     1       60710211        60710260        +       .       .
	my @cols = split(/\t/, $_);
	my $exonSid    = $cols[1];
	my $label      = $cols[2];
	my $chr        = $cols[4];
	my $feat_start = $cols[5];
	my $feat_end   = $cols[6];

	push(@{$exonID_data->{$exonSid}->{$chr}}, [$feat_start, $feat_end, $label]);
  }
  close EU;

  my @exonSIds;
  map {push(@exonSIds, "'".$_."'")} keys %$exonID_data;
  my $exonSIDs = join(',', @exonSIds);

  # make sure that assembly_type that an exon_stable_id maps to is
  # on the same chr as col. 5 in eucomm data

  # s.name returns name of assembly_type, eg, chr1-02, in the vega database
  my $sql = $vega_db->prepare(qq{
								 SELECT es.stable_id, s.name
								 FROM exon_stable_id es, exon e, seq_region s
								 WHERE es.stable_id in ($exonSIDs)
								 AND es.exon_id=e.exon_id
								 AND e.seq_region_id=s.seq_region_id
								 AND s.coord_system_id=1
								}
							 );
  $sql->execute();

  my $ok;
  my $atype_feats = {};

  while ( my ($exSID, $atype) = $sql->fetchrow() ) {
	$atype =~ /chr(.+)-\d+/;
	my $chr_a = $1;

	foreach my $chr_b (keys %{$exonID_data->{$exSID}} ){
	  if ($chr_b ne $chr_a){
		warn "Features: $exSID\n";
		map {warn "@$_\n"} @{$exonID_data->{$exSID}->{$chr_b}};
		warn "mapped to different chromosomes: [$chr_a vs $chr_b]\n";
	  }
	  else {
		$ok = 1;
		push(@{$atype_feats->{$atype}->{$chr_b}}, @{$exonID_data->{$exSID}->{$chr_b}});
	  }
	}
  }
  if ( $ok ){
	$exonID_data = {}; # discard
	return $atype_feats;
  }
  else {
	die "Discrepancies in Eucomm mapping!";
  }
}

sub connect_vega_db {

  my $dbname = shift;

  my $dbh = DBI->connect("DBI:mysql:$dbname:vegabuild:3304", "ottro", "", {RaiseError => 1})
        || die "cannot connect to $dbname, $DBI::errstr";
  return $dbh;
}

__END__
