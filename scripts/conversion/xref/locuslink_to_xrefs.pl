#!/usr/local/bin/perl

use strict;

use Bio::Otter::DBSQL::DBAdaptor;
use Getopt::Long;

my $host   = 'ecs4';
my $user   = 'ensadmin';
my $pass   = '';
my $port   = 3352;
my $dbname = 'mouse_vega040719_xref';

my $lltmpl_file = "/acari/work2/th/work/vega/files/LL_tmpl.gz";

my @chromosomes;
my $path = 'VEGA';
my $do_store = 0;
my @gene_stable_ids;

my $organism='human';

my $opt_h;
my $opt_v;
my $opt_t;
my $opt_o;

$| = 1;

&GetOptions(
	    'host:s'              => \$host,
	    'user:s'              => \$user,
	    'dbname:s'            => \$dbname,
	    'pass:s'              => \$pass,
	    'path:s'              => \$path,
	    'port:n'              => \$port,
	    'chromosomes:s'       => \@chromosomes,
	    'lltmpl_file:s'       => \$lltmpl_file,
	    'organism:s'          => \$organism,
	    'gene_stable_id:s'    => \@gene_stable_ids,
	    'store'               => \$do_store,
	    'h'                   => \$opt_h,
	    'v'                   => \$opt_v,
	    't'                   => \$opt_t,
	    'o:s'                 => \$opt_o,
);

if($opt_h){
    print<<ENDOFTEXT;
locuslink_to_xrefs.pl

  -host           host    host of mysql instance ($host)
  -dbname         dbname  database ($dbname)
  -port           port    port ($port)
  -user           user    user ($user)
  -pass           pass    password 

  -path           path    path ($path)
  -organism       org     organism ($organism)
  -store                  write xrefs to database
  -chromosomes    chr,[chr]

  -h                      this help
  -v                      verbose
ENDOFTEXT
    exit 0;
}

if (scalar(@chromosomes)) {
  @chromosomes = split (/,/, join (',', @chromosomes));
}

my %gene_stable_ids;
if (scalar(@gene_stable_ids)) {
  my $gene_stable_id=$gene_stable_ids[0];
  if(scalar(@gene_stable_ids)==1 && -e $gene_stable_id){
    # 'gene' is a file
    @gene_stable_ids=();
    open(IN,$gene_stable_id) || die "cannot open $gene_stable_id";
    while(<IN>){
      chomp;
      push(@gene_stable_ids,$_);
    }
    close(IN);
  }else{
    @gene_stable_ids = split (/,/, join (',', @gene_stable_ids));
  }
  print "Using list of ".scalar(@gene_stable_ids)." gene stable ids\n";
  %gene_stable_ids = map {$_,1} @gene_stable_ids;
}

# translate organism to correct name used by LLtmpl file
my $org;
{
  my %org;
  %org=(
	'human'=>'Homo sapiens',
	'mouse'=>'Mus musculus',
	'zebrafish'=>'Danio rerio',
	);
  if($org{$organism}){
    $org=$org{$organism};
  }else{
    print "ERR organism \'$organism\' not recognised\n";
    exit 0;
  }
}

my $db = new Bio::Otter::DBSQL::DBAdaptor(
  -host   => $host,
  -user   => $user,
  -port   => $port,
  -pass   => $pass,
  -dbname => $dbname
);
$db->assembly_type($path);

my $sa  = $db->get_SliceAdaptor();
my $aga = $db->get_GeneAdaptor();
my $adx = $db->get_DBEntryAdaptor();

my $chrhash = get_chrlengths($db,$path);

#filter to specified chromosome names only
if (scalar(@chromosomes)) {
  foreach my $chr (@chromosomes) {
    my $found = 0;
    foreach my $chr_from_hash (keys %$chrhash) {
      if ($chr_from_hash =~ /^${chr}$/) {
        $found = 1;
        last;
      }
    }
    if (!$found) {
      print "Didn't find chromosome named $chr in database $dbname\n";
    }
  }
  HASH: foreach my $chr_from_hash (keys %$chrhash) {
    foreach my $chr (@chromosomes) {
      if ($chr_from_hash =~ /^${chr}$/) { next HASH; }
    }
    delete($chrhash->{$chr_from_hash});
  }
}

my %locus;
my %seqname;

# parse and index LLtmpl file:
# pos -> set to >>
# index off OFFICIAL_SYMBOL
if($opt_o){
  open(OUT,">$opt_o") || die "cannot open $opt_o";
}
if($lltmpl_file=~/\.gz$/){
  open(FPLLT,"gzip -d -c $lltmpl_file |") or die "cannot open $lltmpl_file";
}else{
  open(FPLLT,$lltmpl_file) or die "cannot open $lltmpl_file";
}
my %lltmp;
my %lcmap;
{
  my $nok=0;
  my $nworg=0;
  my $nmorg=0;
  my $nmsym=0;
  my $locus_id;
  my $pos=0;
  my $flag_found=0;
  my $flag_org=0;
  my $nm='';
  my $np='';
  my $desc='';
  my $gene_name='';
  while(<FPLLT>){
    if(/^SUMMARY: (.*)/){
      $desc = $1;
    }elsif(/^NM: (.*)/){
      $nm = $1;
      $nm =~ s/\|.*//;
    }elsif(/^NP: (.*)/){
      $np = $1;
      $np =~ s/\|.*//;
    }elsif(/^ORGANISM: (.*)/){
      my $org2=$1;
      if($org eq $org2){
	$flag_org=1;
      }else{
	$flag_org=2;
      }
    }elsif(/^OFFICIAL_SYMBOL: (\w+)/){
      if($flag_org==1){
	$gene_name=$1;
	my $lc_gene_name=lc($gene_name);
	push(@{$lcmap{$lc_gene_name}},$gene_name);
	$nok++;
      }elsif($flag_org==2){
	# skip - wrong organism
	$nworg++;
      }elsif($flag_org==0){
	print "WARN: organism not found for $locus_id\n";
	$nmorg++;
      }
      $flag_org=0;
      $flag_found=0;
    }elsif(/\>\>(\d+)/){
      if($gene_name){
      	$lltmp{$gene_name}=[$nm,$np,$locus_id,$desc];
	print OUT "$gene_name\t$nm\t$np\t$locus_id\t$desc\n" if $opt_o;
	$nm='';
	$np='';
	$desc='';
      }
      if($flag_found){
	$nmsym++;
	print "WARN: OFFICIAL_SYMBOL for $locus_id not found\n" if $opt_v;
      }
      $flag_found=1;
      $locus_id=$1;
    }
  }
  print "$nok entries indexed ok\n";
  print "$nworg entries skipped - not \'$organism\'\n";
  print "$nmorg entries skipped - no organism label\n";
  print "$nmsym entries skipped - no official symbol\n";
}

foreach my $chr (reverse sort bychrnum keys %$chrhash) {
  print STDERR "Chr $chr from 1 to " . $chrhash->{$chr} . " on " . $path . "\n";
  my $chrstart = 1;
  my $chrend   = $chrhash->{$chr};

  my $slice = $sa->fetch_by_chr_start_end($chr, 1, $chrhash->{$chr});

  print "Fetching genes\n";
  my $genes = $aga->fetch_by_Slice($slice);
  print "Fetched (".scalar(@$genes).") genes\n";
  my $nfound=0;
  my $ncase=0;
  my $nclone=0;
  my $nmiss=0;
  foreach my $gene (@$genes) {
    my $gsi=$gene->stable_id;
    if(scalar(@gene_stable_ids)){
      next unless $gene_stable_ids{$gsi};
    }
    my $gene_name;
    if ($gene->gene_info->name && $gene->gene_info->name->name) {
      $gene_name = $gene->gene_info->name->name;
    } else {
      die "Failed finding gene name for " .$gene->stable_id . "\n";
    }
    my $lc_gene_name=lc($gene_name);

    # lookup this gene name
    if($lltmp{$gene_name}){

      print "  Found locuslink match for $gene_name\n";
      $nfound++;
      my($nm,$np,$locus_id,$desc)=@{$lltmp{$gene_name}};

      my $dbentry=Bio::EnsEMBL::DBEntry->new(-primary_id=>$locus_id,
                                             -display_id=>$gene_name,
                                             -version=>1,
                                             -release=>1,
                                             -dbname=>"LocusLink",
                                            );
      print "   locus link = " .$locus_id . "\n" if $opt_v;
      $dbentry->status('KNOWN');
      $gene->add_DBEntry($dbentry);
      $adx->store($dbentry,$gene->dbID,'Gene') if $do_store;

      # Display xref id update
      my $sth = $db->prepare("update gene set display_xref_id=" . 
                             $dbentry->dbID . " where gene_id=" . $gene->dbID);
      print "    ". $sth->{Statement} . "\n" if $opt_v;
      $sth->execute if $do_store;

      if ($nm) {
	print "   RefSeq NM = " .$nm . "\n" if $opt_v;
        my $dbentry=Bio::EnsEMBL::DBEntry->new(-primary_id=>$nm,
                                               -display_id=>$nm,
                                               -version=>1,
                                               -release=>1,
                                               -dbname=>"RefSeq",
                                              );
        $dbentry->status('KNOWNXREF');
        $gene->add_DBEntry($dbentry);
        $adx->store($dbentry,$gene->dbID,'Gene') if $do_store;
      }
    }elsif($lcmap{$lc_gene_name}){
      # check if case in database might be wrong, by doing lc comparision
	print "  WARN: Possible case error for $gene_name: ".
	    join(',',(@{$lcmap{$lc_gene_name}}))."\n";
	$ncase++;
    }elsif($gene_name=~/^\w+\.\d+$/ || $gene_name=~/^\w+\-\w+\.\d+$/){
      # probably a clone based genename - ok
      print "  No locuslink match for $gene_name\n" if $opt_v;
      $nclone++;
    }else{
      # doesn't look like a clone name, so perhaps mistyped 
      print "  WARN: No locuslink match for $gene_name\n";
      $nmiss++;
    }
  }
  print " Locuslink information for $nfound genes added\n";
  print " $ncase names mismatch because of possible wrong case\n";
  print " $nclone names appear to be based on clonename - no match expected\n";
  print " $nmiss other names - match expected\n";
}
close(FPLLT);

sub get_chrlengths{
  my $db = shift;
  my $type = shift;

  if (!$db->isa('Bio::EnsEMBL::DBSQL::DBAdaptor')) {
    die "get_chrlengths should be passed a Bio::EnsEMBL::DBSQL::DBAdaptor\n";
  }

  my %chrhash;

  my $q = qq( SELECT chrom.name,max(chr_end) FROM assembly as ass, chromosome as chrom
              WHERE ass.type = '$type' and ass.chromosome_id = chrom.chromosome_id
              GROUP BY chrom.name
            );

  my $sth = $db->prepare($q) || $db->throw("can't prepare: $q");
  my $res = $sth->execute || $db->throw("can't execute: $q");

  while( my ($chr, $length) = $sth->fetchrow_array) {
    $chrhash{$chr} = $length;
  }
  return \%chrhash;
}


sub bychrnum {

  my @awords = split /_/, $a;
  my @bwords = split /_/, $b;

  my $anum = $awords[0];
  my $bnum = $bwords[0];

  #  if ($anum !~ /^chr/ || $bnum !~ /^chr/) {
  #    die "Chr name doesn't begin with chr for $a or $b";
  #  }

  $anum =~ s/chr//;
  $bnum =~ s/chr//;

  if ($anum !~ /^[0-9]*$/) {
    if ($bnum !~ /^[0-9]*$/) {
      return $anum cmp $bnum;
    } else {
      return 1;
    }
  }
  if ($bnum !~ /^[0-9]*$/) {
    return -1;
  }

  if ($anum <=> $bnum) {
    return $anum <=> $bnum;
  } else {
    if ($#awords == 0) {
      return -1;
    } elsif ($#bwords == 0) {
      return 1;
    } else {
      return $awords[1] cmp $bwords[1];
    }
  }
}

