#!/usr/local/bin/perl

use strict;

use Getopt::Long;

use Bio::Otter::DBSQL::DBAdaptor;

my $t_host    = 'ecs2a';
my $t_user    = 'ensadmin';
my $t_pass    = 'ensembl';
my $t_port    = 3306;
my $t_dbname  = 'otter_merged_chrs_with_anal_test';

my $chr      = 21;

&GetOptions( 't_host:s'   => \$t_host,
             't_user:s'   => \$t_user,
             't_pass:s'   => \$t_pass,
             't_port:s'   => \$t_port,
             't_dbname:s' => \$t_dbname,
             'chr:s'      => \$chr,
            );

if (!defined($chr)) {
  die "Missing required args\n";
}

my $tdb = new Bio::Otter::DBSQL::DBAdaptor(-host => $t_host,
                                           -user => $t_user,
                                           -pass => $t_pass,
                                           -port => $t_port,
                                           -dbname => $t_dbname);



my $row;
foreach my $table (('prediction_transcript','simple_feature','protein_align_feature',
                    'dna_align_feature','repeat_feature')) {
  my $sth = $tdb->prepare("select distinct contig_id from assembly where assembly.chromosome_id=$chr");
  $sth->execute;
  while ($row = $sth->fetchrow_hashref) {
    my $contig = $row->{'contig_id'};
    my $sth1 = $tdb->prepare("delete from $table where $table.contig_id = $contig");
    print $sth1->{Statement} . "\n";
    $sth1->execute;
  }
}

my $sth = $tdb->prepare("select distinct contig.clone_id from assembly,contig where assembly.chromosome_id=$chr and contig.contig_id=assembly.contig_id");
$sth->execute;
while ($row = $sth->fetchrow_hashref) {
  my $clone = $row->{'clone_id'};
  my $sth1 = $tdb->prepare("delete from clone where clone.clone_id = $clone");
  $sth1->execute;
  print $sth1->{Statement} . "\n";
}

my $sth = $tdb->prepare("select distinct contig.dna_id from assembly,contig where assembly.chromosome_id=$chr and contig.contig_id=assembly.contig_id");
$sth->execute;
while ($row = $sth->fetchrow_hashref) {
  my $dna = $row->{'dna_id'};
  my $sth1 = $tdb->prepare("delete from dna where dna.dna_id = $dna");
  $sth1->execute;
  print $sth1->{Statement} . "\n";
}

my $sth = $tdb->prepare("select distinct contig_id from assembly where assembly.chromosome_id=$chr");
$sth->execute;
while ($row = $sth->fetchrow_hashref) {
  my $contig = $row->{'contig_id'};
  my $sth1 = $tdb->prepare("delete from assembly where assembly.contig_id = $contig");
  $sth1->execute;
  print $sth1->{Statement} . "\n";
  my $sth2 = $tdb->prepare("delete from contig where contig.contig_id = $contig");
  print $sth2->{Statement} . "\n";
  $sth2->execute;
}
my $sth2 = $tdb->prepare("delete from chromosome where chromosome_id=$chr");
$sth2->execute;
print $sth2->{Statement} . "\n";
