#!/usr/local/bin/perl

use strict;

use Getopt::Long;

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::EnsEMBL::Slice;
use Bio::EnsEMBL::RawContig;
use Bio::EnsEMBL::Translation;
use Bio::EnsEMBL::Clone;
use Bio::Seq;
use Bio::SeqIO;


my $host    = 'ecs2e';
my $user    = 'ensadmin';
my $pass    = '';
my $port    = 3306;
my $dbname  = 'human_ncbi34_raw';
my $path     = 'NCBI34';

&GetOptions( 'host:s'   => \$host,
             'user:s'   => \$user,
             'pass:s'   => \$pass,
             'port:s'   => \$port,
             'dbname:s' => \$dbname,
             'path:s'   => \$path,
            );

my $tdb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host => $host,
                                             -user => $user,
                                             -pass => $pass,
                                             -port => $port,
                                             -dbname => $dbname);


my $chrhash = get_chrlengths($tdb, $path);

my $chr;
my $len;
while (($chr, $len) = each %$chrhash) {
  print "Chr $chr length $len\n";
  my $sth = $tdb->prepare("update chromosome set length=$len where name='$chr'");
  $sth->execute();
  $sth->finish;
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
    print "chr = $chr length = $length\n";
    $chrhash{$chr} = $length;
  }
  return \%chrhash;
}


