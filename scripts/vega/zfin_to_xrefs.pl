#!/usr/local/bin/perl

# produces xrefs for the genes listed in our weekly ZFIN downloads (see below)

use strict;

use Bio::Otter::DBSQL::DBAdaptor;
use Getopt::Long;

my $host   = 'ecs4';
my $user   = 'ensadmin';
my $pass   = 'ensembl';
my $port   = 3351;
my $dbname = 'zfish_vega_1104';
my $zfinfile='/nfs/disk100/zfishpub/ZFIN/downloads/zfin_genes.txt';

my @chromosomes;
my $path = 'VEGA';
my $do_store = 0;

$| = 1;

&GetOptions(
  'host:s'        => \$host,
  'user:s'        => \$user,
  'dbname:s'      => \$dbname,
  'pass:s'        => \$pass,
  'path:s'        => \$path,
  'port:n'        => \$port,
  'chromosomes:s' => \@chromosomes,
  'zfinfile:s'     => \$zfinfile,
  'store'         => \$do_store,
);

if (scalar(@chromosomes)) {
  @chromosomes = split (/,/, join (',', @chromosomes));
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

# get names matched to ZFIN entries
my %crossrefs;
open(IN,$zfinfile) or die "cannot open $zfinfile";
while (<IN>) {
    my ($zfinid,$desc,$name,$lg) = split /\t/;
    $crossrefs{$name}->{zfinid} = $zfinid;
    $crossrefs{$name}->{desc}   = $desc;
}


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

    if (($crossrefs{$gene_name})) {
      print "Found ZFIN match for $gene_name\n";
      my $dbentry=Bio::EnsEMBL::DBEntry->new(-primary_id=>$crossrefs{$gene_name}->{zfinid},
                                             -display_id=>$gene_name,
                                             -version=>1,
                                             -release=>1,
                                             -dbname=>"ZFIN",
                                            );
      print " ZFIN = $gene_name, ".$crossrefs{$gene_name}->{zfinid}."\n";
      $dbentry->status('KNOWNXREF');
      $gene->add_DBEntry($dbentry);
      if ($do_store) {
          $adx->store($dbentry,$gene->dbID,'Gene') or die "Couldn't store entry\n";
      }    
      print "generated ",$dbentry->dbID,"\n" if $do_store;

      # Display xref id update
      my $sth = $db->prepare("update gene set display_xref_id=" . 
                             $dbentry->dbID . " where gene_id=" . $gene->dbID);
      print $sth->{Statement} . "\n";
      $sth->execute if $do_store;

    } else {
      print "No ZFIN match for $gene_name\n";
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

