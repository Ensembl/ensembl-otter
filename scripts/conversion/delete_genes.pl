#!/usr/local/bin/perl

use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Getopt::Long;

my $host   = 'ecs2c';
my $user   = 'ensadmin';
my $pass   = 'ensembl';
my $dbname = 'otter_chr20_old_annotation';
my $port   = 19322;
my @types;

$| = 1;

&GetOptions(
  'host:s'   => \$host,
  'user:s'   => \$user,
  'pass:s'   => \$pass,
  'dbname:s' => \$dbname,
  'port:n'   => \$port,
  'types:s'  => \@types,
);

if (scalar(@types)) {
  @types = split(/,/,join(',',@types));
}

my $db = new Bio::EnsEMBL::DBSQL::DBAdaptor(
  -host   => $host,
  -user   => $user,
  -port   => $port,
  -dbname => $dbname,
  -pass   => $pass,
);


my $ga = $db->get_GeneAdaptor();


foreach my $type (@types) {
  print STDERR "Type $type\n";

  my $sth = $db->prepare("select distinct gene_id from gene where type=\'$type\'");
  $sth->execute;
  while ($row = $sth->fetchrow_hashref) {


    $gene = $ga->fetch_by_dbID($row->{gene_id});

    print $gene->stable_id . "\n";
    $ga->remove($gene);
  }
}

