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
my $nomeid_file = undef;
my @gene_stable_ids;

my $opt_h;

$| = 1;

&GetOptions(
	    'host:s'              => \$host,
	    'dbname:s'            => \$dbname,
	    'port:n'              => \$port,
	    'user:s'              => \$user,
	    'pass:s'              => \$pass,
	    'path:s'              => \$path,
	    'chromosomes:s'       => \@chromosomes,
	    'nomeidfile:s'        => \$nomeid_file,
	    'gene_stable_id:s'    => \@gene_stable_ids,
	    'store'               => \$do_store,
	    'h'                   => \$opt_h,
);

if($opt_h){
  print<<ENDOFTEXT;
hugo_to_xrefs.pl

  -host           host    host of mysql instance ($host)
  -dbname         dbname  database ($dbname)
  -port           port    port ($port)
  -user           user    user ($user)
  -pass           pass    password 

  -path           path    path ($path)
  -chromosomes    chr,[chr]
  -nomeidfile     file    HUGO nomenclature file
  -store                  write xrefs to database

  -gene_stable_id gsi[,gsi] (list or file containing list)

  -h                      this help
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

open FPNOM, "<$nomeid_file" or die "Couldn't open file $nomeid_file\n";
my $line = <FPNOM>;
chomp $line;
my @fieldnames = split /\t/,$line;
my %hugohash;
while (<FPNOM>) {
  chomp;
  my @fields = split /\t/,$_,-1;

  if (scalar(@fields) != scalar(@fieldnames)) {
    print "Got " . scalar(@fields) . " and " . scalar(@fieldnames) . "\n";
    die "Inconsistent number of fields for $_";
  }
  my $i=0;
#   foreach my $field (@fields) {
#     print "Field " . $fieldnames[$i++] . " = " . $field . "\n";
#   } 
#   print "#################\n";
  if (defined($hugohash{$fields[1]})) {
    die "Duplicate lines for " . $fields[1];
  }
  $hugohash{$fields[1]} = \@fields;
}

my %convhash;
$convhash{MIM}="MIM";
$convhash{"Ref Seq"}="RefSeq";
$convhash{"Locus Link"}="LocusLink";
$convhash{"SWISSPROT"}="SWISSPROT";

foreach my $chr (reverse sort bychrnum keys %$chrhash) {
  print STDERR "Chr $chr from 1 to " . $chrhash->{$chr} . " on " . $path . "\n";
  my $chrstart = 1;
  my $chrend   = $chrhash->{$chr};

  my $slice = $sa->fetch_by_chr_start_end($chr, 1, $chrhash->{$chr});

  print "Fetching genes\n";
  my $genes = $aga->fetch_by_Slice($slice);
  print "Done fetching genes\n";

  my $nhugo=0;
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

    # Human hugo symbols are meant to be upper case apart from orfs.
    # There's one which isn't (IL27w).
    my $uc_gene_name;
    if ($gene_name =~ /C.*orf[0-9]*/) {
      $uc_gene_name = $gene_name;
    } else {
      $uc_gene_name = uc $gene_name;
    }

    if (defined($hugohash{$uc_gene_name})) {
      print "Found hugo match for $gene_name\n";
      $nhugo++;
      my $dbentry=Bio::EnsEMBL::DBEntry->new(-primary_id=>$hugohash{$uc_gene_name}->[0],
                                             -display_id=>$gene_name, 
                                             -version=>1,
                                             -release=>1,
                                             -dbname=>"HUGO",
                                            );
      $dbentry->status('KNOWN');
      $gene->add_DBEntry($dbentry);
      $adx->store($dbentry,$gene->dbID,'Gene') if $do_store;

      # Display xref id update
      my $sth = $db->prepare("update gene set display_xref_id=?". 
			     " where gene_id=?");
      $sth->execute($dbentry->dbID,$gene->dbID) if $do_store;

      for (my $i=4;$i<13;$i++) {
        my $xid = $hugohash{$uc_gene_name}->[$i];
        if (exists($convhash{$fieldnames[$i]}) && $xid ne "") {
          my $dbentry=Bio::EnsEMBL::DBEntry->new(-primary_id=>$xid,
                                                 -display_id=>$xid, 
                                                 -version=>1,
                                                 -release=>1,
                                                 -dbname=>$convhash{$fieldnames[$i]},
                                                );
          if ($fieldnames[$i] eq "SWISSPROT") {
            $dbentry->status('XREF');
          } else {
            $dbentry->status('KNOWNXREF');
          }
          $gene->add_DBEntry($dbentry);
          #print "Would have added $convhash{$fieldnames[$i]} with $xid\n"
          $adx->store($dbentry,$gene->dbID,'Gene') if $do_store;
        }
      }
    } else {
      print "No hugo match for $gene_name\n";
    }
  }
  print "$nhugo HUGO names found for chromosome $chr\n";
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

