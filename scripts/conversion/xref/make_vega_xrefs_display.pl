#!/usr/local/bin/perl

use strict;

use Bio::Otter::DBSQL::DBAdaptor;
use Getopt::Long;

my $host   = 'ecs2a';
my $user   = 'ensro';
my $pass   = '';
my $port   = 3306;
my $dbname = 'steve_ensembl_vega_ncbi31_2';
my $dbentry_type = "Vega";

my @chromosomes;
my $path = 'NCBI31';
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
  'dbentry_type:s'=> \$dbentry_type,
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




foreach my $chr (reverse sort bychrnum keys %$chrhash) {
  print STDERR "Chr $chr from 1 to " . $chrhash->{$chr} . "\n";
  my $chrstart = 1;
  my $chrend   = $chrhash->{$chr};

  my $slice = $sa->fetch_by_chr_start_end($chr, 1, $chrhash->{$chr});

  print "Fetching genes\n";
  my $genes = $aga->fetch_by_Slice($slice);
  print "Done fetching genes\n";

  foreach my $gene (@$genes) {
    my @dbentries = @{$gene->get_all_DBLinks};

    my $display_dbentry = undef;
    my $locuslink_dbentry = undef;
    my $type = $dbentry_type . "_gene";
    foreach my $dbentry (@dbentries) {
      if ($dbentry->dbname =~ /$type/) {
        $display_dbentry = $dbentry;
      } 
      if ($dbentry->dbname =~ /LocusLink/) {
        $locuslink_dbentry = $dbentry;
      } 
    }
    # if (defined($locuslink_dbentry)) {
    #   $display_dbentry = $locuslink_dbentry;
    # }
    if (defined($display_dbentry)) {
      my $sth = $db->prepare("update gene set display_xref_id=" . 
                             $display_dbentry->dbID . 
                           " where gene_id=" . $gene->dbID);
      print $sth->{Statement} . ";\n";
    } else {
      print "No $dbentry_type match for ". $gene->stable_id ." dbID " . $gene->dbID ."\n";
    }

    foreach my $trans (@{$gene->get_all_Transcripts}){
      my @dbentries = @{$trans->get_all_DBLinks};
      my $display_dbentry = undef;
      foreach my $dbentry (@dbentries) {
        my $type = $dbentry_type . "_transcript";
        if ($dbentry->dbname =~ /$type/) {
          $display_dbentry = $dbentry;
        } 
      }
      if (defined($display_dbentry)) {
        my $sth = $db->prepare("update transcript set display_xref_id=" . 
                               $display_dbentry->dbID . 
                             " where transcript_id=" . $trans->dbID);
        print $sth->{Statement} . ";\n";
      } else {
        print "No $dbentry_type match for ". $trans->stable_id ."\n";
      }
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

