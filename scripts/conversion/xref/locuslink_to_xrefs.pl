#!/usr/local/bin/perl

use strict;

use Bio::Otter::DBSQL::DBAdaptor;
use Getopt::Long;

my $host   = 'ecs4';
my $user   = 'ensadmin';
my $pass   = ;
my $port   = 3352;
my $dbname = 'mouse_vega040719_xref';

my $lltmpl_file = "/acari/work2/th/work/vega/files/LL_tmpl.gz";

my @chromosomes;
my $path = 'VEGA';
my $do_store = 0;

my $organism='human';

$| = 1;

&GetOptions(
  'host:s'        => \$host,
  'user:s'        => \$user,
  'dbname:s'      => \$dbname,
  'pass:s'        => \$pass,
  'path:s'        => \$path,
  'port:n'        => \$port,
  'chromosomes:s' => \@chromosomes,
  'gfffile:s'     => \$gff_file,
  'lltmpl_file:s' => \$lltmpl_file,
  'organism:s'    => \$organism,
  'store'         => \$do_store,
);

if (scalar(@chromosomes)) {
  @chromosomes = split (/,/, join (',', @chromosomes));
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
if($lltmpl_file=~/\.gz$/){
  open(FPLLT,"gzip -d -c $lltmpl_file |") or die "cannot open $lltmpl_file";
}else{
  open(FPLLT,$lltmpl_file) or die "cannot open $lltmpl_file";
}
my %loctmplindex;
{
  my $nok=0;
  my $nworg=0;
  my $nmorg=0;
  my $nmsym=0;
  my $llid;
  my $pos=0;
  my $flag_found=0;
  my $flag_org=0;
  while(<FPLLT>){
    if(/^LOCUSID: (.*)/){
    }elsif(/^ORGANISM: (.*)/){
      my $org2=$1;
      if($org eq $org2){
	$flag_org=1;
      }else{
	$flag_org=2;
      }
    }elsif(/^OFFICIAL_SYMBOL: (\w+)/){
      if($flag_org==1){
	$loctmplindex{$1}=$pos;
	$nok++;
      }elsif($flag_org==2){
	# skip - wrong organism
	$nworg++;
      }elsif($flag_org==0){
	print "WARN: organism not found for $llid\n";
	$nmorg++;
      }
      $flag_org=0;
      $flag=0;
    }elsif(/\>\>(\d+)/){
      $pos = tell FPLLT;
      if($flag){
	$nmsym++;
	print "WARN: $llid was not saved\n";
      }
      $flag=1;
      $llid=$1;
    }
  }
  print "$nok entries indexed ok\n";
  print "$nworg entries skipped - not \'$organism\'\n";
  print "$nmorg entries skipped - no organism label\n";
  print "$nmsym entries skipped - no official symbol\n";
  exit 0;
}

my %crossrefs;

open(IN,$gff_file) or die "cannot open $gff_file";
while(<IN>){
  if(/locus_id\s+\"([^\"]+)\"/){
    my $locus_id = $1;
    my $gene_id = $_;
    /gene_id\s+\"([^\"]+)\"/;
    my $gene_id = $1;
    if ($locus_id ne "undef") {
      seek FPLLT, $loctmplindex{$locus_id},"SEEK_SET" ;
      my $line = <FPLLT>;
      my $off_sym;
      my $nm;
      my $np;
      my $desc;
      while (<FPLLT>) {
        last if (/^LOCUSID:/); 
        if (/^OFFICIAL_SYMBOL: (.*)/) {
          $off_sym = $1;
        } elsif (/^SUMMARY: (.*)/) {
          $desc = $1;
        } elsif (/^NM: (.*)/) {
          $nm = $1;
          $nm =~ s/\|.*//;
        } elsif (/^NP: (.*)/) {
          $np = $1;
          $np =~ s/\|.*//;
        }
      }
            
      print $line;
      print "Gene $gene_id locuslink $locus_id\n";
      if ($off_sym) { print " offsym = $off_sym\n"; }
      $locus{$locus_id}++;
      $crossrefs{$gene_id}->{locus_id} = $locus_id;
      $crossrefs{$gene_id}->{off_sym} = ($off_sym ? $off_sym : $locus_id);
      $crossrefs{$gene_id}->{nm} = $nm if defined($nm);
      $crossrefs{$gene_id}->{np} = $nm if defined($np);
    }
  }
}
close(IN);
close(FPLLT);
print scalar(keys %locus)." locus ids found\n";


foreach my $chr (reverse sort bychrnum keys %$chrhash) {
  print STDERR "Chr $chr from 1 to " . $chrhash->{$chr} . " on " . $path . "\n";
  my $chrstart = 1;
  my $chrend   = $chrhash->{$chr};

  my $slice = $sa->fetch_by_chr_start_end($chr, 1, $chrhash->{$chr});

  print "Fetching genes\n";
  my $genes = $aga->fetch_by_Slice($slice);
  print "Done fetching genes\n";

  foreach my $gene (@$genes) {
    my $gene_name;
    if ($gene->gene_info->name && $gene->gene_info->name->name) {
      $gene_name = $gene->gene_info->name->name;
    } else {
      die "Failed finding gene name for " .$gene->stable_id . "\n";
    }

    if (defined($crossrefs{$gene_name})) {
      print "Found locuslink match for $gene_name\n";
      my $dbentry=Bio::EnsEMBL::DBEntry->new(-primary_id=>$crossrefs{$gene_name}->{locus_id},
                                             -display_id=>$crossrefs{$gene_name}->{off_sym},
                                             -version=>1,
                                             -release=>1,
                                             -dbname=>"LocusLink",
                                            );
      print " locus link = " .$crossrefs{$gene_name}->{off_sym} . "\n";
      $dbentry->status('KNOWN');
      $gene->add_DBEntry($dbentry);
      $adx->store($dbentry,$gene->dbID,'Gene') if $do_store;

  # Display xref id update
      my $sth = $db->prepare("update gene set display_xref_id=" . 
                             $dbentry->dbID . " where gene_id=" . $gene->dbID);
      print $sth->{Statement} . "\n";
      $sth->execute if $do_store;

      if ($crossrefs{$gene_name}->{nm}) {
        my $dbentry=Bio::EnsEMBL::DBEntry->new(-primary_id=>$crossrefs{$gene_name}->{nm},
                                               -display_id=>$crossrefs{$gene_name}->{nm},
                                               -version=>1,
                                               -release=>1,
                                               -dbname=>"RefSeq",
                                              );
        $dbentry->status('KNOWNXREF');
        $gene->add_DBEntry($dbentry);
        $adx->store($dbentry,$gene->dbID,'Gene') if $do_store;
      }
    } else {
      print "No locuslink match for $gene_name\n";
    }
  }
}

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

