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


my $host    = 'ecs1d';
my $user    = 'ensro';
my $pass    = undef;
my $port    = 19322;
my $dbname  = 'chr9p12_assembled';

my $chr      = 9;
my $path     = 'SANGER';

&GetOptions( 'host:s'=> \$host,
             'user:s'=> \$user,
             'pass:s'=> \$pass,
             'port:s'=> \$port,
             'dbname:s'  => \$dbname,
             'chr:s'     => \$chr,
             'path:s'  => \$path,
            );

my $tdb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host => $host,
                                             -user => $user,
                                             -pass => $pass,
                                             -port => $port,
                                             -dbname => $dbname);


$tdb->assembly_type($path);

my $slice = $tdb->get_SliceAdaptor()->fetch_by_chr_name($chr);

my $seq = $slice->seq;
$seq =~ s/(.{80})/$1\n/g;
print $seq . "\n";
exit;

