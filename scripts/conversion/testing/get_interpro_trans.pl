#!/usr/local/bin/perl


use strict;
use Bio::Otter::DBSQL::DBAdaptor;
use Getopt::Long;

my $host   = 'ecs2c';
my $user   = 'ensro';
my $dbname = 'otter_chr13_with_anal';
my @chromosomes;
my $file = 'stdout';

my $path = 'SANGER_06';
my $port = 19322;

my @ignore_prefs;

$| = 1;

&GetOptions(
  'host:s'   => \$host,
  'user:s'   => \$user,
  'dbname:s' => \$dbname,
  'path:s'   => \$path,
  'port:n'   => \$port,
  'chromosomes:s' => \@chromosomes,
  'ignore:s' => \@ignore_prefs,
  'file:s' => \$file
);

if (scalar(@chromosomes)) {
  @chromosomes = split(/,/,join(',',@chromosomes));
}

if (scalar(@ignore_prefs)) {
  @ignore_prefs = split(/,/,join(',',@ignore_prefs));
}

my $db = new Bio::Otter::DBSQL::DBAdaptor(
  -host   => $host,
  -user   => $user,
  -port   => $port,
  -dbname => $dbname
);
$db->assembly_type($path);

my $sa  = $db->get_SliceAdaptor();
my $aga = $db->get_AnnotatedGeneAdaptor();
my $pfa = $db->get_ProteinFeatureAdaptor();

my $chrhash = get_chrlengths($db);

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
      if ($chr_from_hash =~ /^${chr}$/) {next HASH;}
    }
    delete($chrhash->{$chr_from_hash});
  }
}


if ($file ne "stdout") {
  open FP,">$file";
} else {
  open FP,">-";
}

foreach my $chr (reverse sort bychrnum keys %$chrhash) {
  print STDERR "Chr $chr from 1 to " . $chrhash->{$chr}. "\n";
  my $chrstart = 1;
  my $chrend   = $chrhash->{$chr};

  my $slice = $sa->fetch_by_chr_name($chr);

  print "Fetching genes\n";
  my @genes = @{$aga->fetch_by_Slice($slice)};
#  my $genes = @{$slice->get_all_Genes};
  print "Done fetching genes. Got " . scalar(@genes) . " genes\n";

  my %dom_counts;
  my %dom_descs;

  foreach my $gene (@genes) {
    foreach my $trans (@{$gene->get_all_Transcripts}) {
      my %trans_doms;
      if ($trans->translation) {
        my $prot_feats = $pfa->fetch_by_translation_id($trans->translation->dbID);
        foreach my $feat (@$prot_feats) {
          print "Feature " . $feat->hseqname . " " . $feat->interpro_ac . "\n";
          my $do_ignore = 0;
          foreach my $ignore_pref (@ignore_prefs) {
            if ($feat->hseqname =~ /^$ignore_pref/) {
              $do_ignore = 1;
              last;
            }
          }
          if (!$do_ignore) {
            $trans_doms{$feat->interpro_ac} = 1;
            $dom_descs{$feat->interpro_ac} = $feat->idesc;
          }
        }
      }
      foreach my $iac (keys %trans_doms) {
        $dom_counts{$iac} ++;
      }
    }
  }

  foreach my $iac (keys (%dom_counts)) {
    print $iac . " " . $dom_counts{$iac} . " " . $dom_descs{$iac} ."\n";
  }
}

sub tweak_translateable {
  my ($trans) = @_;

  my @exons = @{$trans->get_all_translateable_Exons};

# The start and end exons may have been clipped
# This hack gives them the stable_id of the unclipped exon
  $exons[0]->stable_id($trans->translation->start_Exon->stable_id);
  $exons[$#exons]->stable_id($trans->translation->end_Exon->stable_id);

  return @exons;
}


# End main


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

sub get_chrlengths {
  my $db   = shift;
  my $type = shift;

  if (!$db->isa('Bio::EnsEMBL::DBSQL::DBAdaptor')) {
    die "get_chrlengths should be passed a Bio::EnsEMBL::DBSQL::DBAdaptor\n";
  }

  my $ca = $db->get_ChromosomeAdaptor();
  my $chroms = $ca->fetch_all();

  my %chrhash;

  foreach my $chr (@$chroms) {
    $chrhash{$chr->chr_name} = $chr->length;
  }
  return \%chrhash;
}

