#!/usr/local/ensembl/bin/perl -w

use strict;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Getopt::Long;

my $host    = 'ecs2a';
my $user    = 'ensro';
my $pass    = '';
my $dbname  = 'steve_otter_merged_chrs';
my $port    = 3306;

my $t_host    = 'ecs2a';
my $t_user    = 'ensadmin';
my $t_pass    = 'ensembl';
my $t_port    = 3306;
my $t_dbname  = 'steve_ensembl_vega_ncbi31_2';

my $chr;
my $path='NCBI31';
my $t_path='NCBI31';

my $help;

&GetOptions( 'host:s'    => \$host,
             'user:s'    => \$user,
             'pass:s'    => \$pass,
             'port:s'    => \$port,
             'dbname:s'  => \$dbname,
             't_host:s'    => \$t_host,
             't_user:s'    => \$t_user,
             't_pass:s'    => \$t_pass,
             't_port:s'    => \$t_port,
             't_dbname:s'  => \$t_dbname,
             'chr:s'       => \$chr,
             'path:s'      => \$path,
             't_path:s'    => \$t_path,
	     'help|h'        => \$help,
            );

if($help){
  print<<ENDOFTEXT;
transfer_clone_annotation.pl
FROM:
  -host           char      host of mysql instance ($host)
  -db             char      database ($dbname)
  -port           num       port ($port)
  -user           char      user ($user)
  -pass           char      passwd
TO:
  -t_host         char      host of mysql instance ($t_host)
  -t_db           char      database ($t_dbname)
  -t_port         num       port ($t_port)
  -t_user         char      user ($t_user)
  -t_pass         char      passwd

  -chr            char      chromosome ($chr)
  -path           char      path ($path)
  -t_path         char      path ($t_path)

  -h                        this help
ENDOFTEXT
    exit 0;
}


my $old_db = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host=>$host,
						-port=>$port,
						-user=>$user,
						-dbname=>$dbname,
						-pass=>$pass,
						);

my $new_db = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host =>$t_host,
						-port=>$t_port,
						-user=>$t_user,
						-dbname=>$t_dbname,
						-pass=>$t_pass,
						);

my %new_contigs;
my $sql;
if($chr){
  $sql = "select distinct(ct.name) from contig ct, assembly a, chromosome c where ct.contig_id=a.contig_id and a.type='$t_path' and a.chromosome_id=c.chromosome_id and c.name='$chr'";
}else{
  $sql = "select distinct(ct.name) from contig ct, assembly a where ct.contig_id=a.contig_id and a.type='$t_path'";
}
my $sth = $new_db->prepare($sql);
$sth->execute;
my $old_rca = $old_db->get_RawContigAdaptor();
my $new_rca = $new_db->get_RawContigAdaptor();
RC: while (my($name) = $sth->fetchrow){
  print "sorting contig ".$name."\n";
  my $old_rc = $old_rca->fetch_by_name($name);

  if(!$old_rc){
    $new_contigs{$name} = 1;
    next RC;
  }

  my $new_rc = $new_rca->fetch_by_name($name);

  my $analysis_adaptor = $new_db->get_AnalysisAdaptor();

  my %analysis_hash;

  my @new_sfs;
  my @simple_features = @{$old_rc->get_all_SimpleFeatures};
  my $sfa = $new_db->get_SimpleFeatureAdaptor;
  foreach my $sf(@simple_features){
    if(!$analysis_hash{$sf->analysis->logic_name}){
      my $analysis=$analysis_adaptor->fetch_by_logic_name($sf->analysis->logic_name);
      if(!$analysis){
	warn "haven't got analysis of type ".$sf->analysis->logic_name." in ".$new_db->dbname." can't store this\n";
      }else{
	$analysis_hash{$analysis->logic_name} = $analysis;
      }
    }
    $sf->contig($new_rc);
    $sf->dbID('');
    $sf->adaptor($sfa);
    $sf->analysis($analysis_hash{$sf->analysis->logic_name});
    push(@new_sfs,$sf);
  }
  $sfa->store(@new_sfs) if scalar(@new_sfs);
}
