#!/usr/local/bin/perl

use strict;

use Bio::Otter::DBSQL::DBAdaptor;
use Getopt::Long;

my $host   = 'ecs2a';
my $user   = 'ensadmin';
my $pass   = 'ensembl';
my $port   = 3306;
my $dbname = 'otter_merged_chrs_with_anal';

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
    my $gene_name;
    if ($gene->gene_info->name && $gene->gene_info->name->name) {
      $gene_name = $gene->gene_info->name->name;
    } else {
      $gene_name = $gene->stable_id;
    }

    my $dbentry=Bio::EnsEMBL::DBEntry->new(-primary_id=>$gene->stable_id,
                                           -display_id=>$gene_name, 
                                           -version=>1,
                                           -release=>1,
                                           -dbname=>"Vega_gene",
                                          );
    $dbentry->status('KNOWN');
    $gene->add_DBEntry($dbentry);
    $adx->store($dbentry,$gene->dbID,'Gene') if $do_store;

    my $sth = $db->prepare("update gene set display_xref_id=" .      
                             $dbentry->dbID .
                           " where gene_id=" . $gene->dbID);
    print $sth->{Statement} . ";\n";
    $sth->execute;


    foreach my $trans (@{$gene->get_all_Transcripts}){
      my $tran_name;
      if ($trans->transcript_info->name) {
        $tran_name = $trans->transcript_info->name;
      } else {
        $tran_name = $trans->stable_id;
      }
      my $dbentry=Bio::EnsEMBL::DBEntry->new(-primary_id=>$trans->stable_id,
                                             -display_id=>$tran_name, 
                                             -version=>1,
                                             -release=>1,
                                             -dbname=>"Vega_transcript",
                                            );
      $dbentry->status('KNOWN');
      $adx->store($dbentry,$trans->dbID,'Transcript') if $do_store;
      my $sth = $db->prepare("update transcript set display_xref_id=" .      
                               $dbentry->dbID .
                             " where transcript_id=" . $trans->dbID);
      $sth->execute;
      print $sth->{Statement} . ";\n";

      print "processing $tran_name\n";

      my $translation = $trans->translation;
      if (defined($translation)) {
        my $dbentry=Bio::EnsEMBL::DBEntry->new(-primary_id=>$translation->stable_id,
                                               -display_id=>$translation->stable_id, 
                                               -version=>1,
                                               -release=>1,
                                               -dbname=>"Vega_translation",
                                              );
        $dbentry->status('KNOWN');
        $adx->store($dbentry,$trans->translation->dbID,'Translation') if $do_store;
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

