#!/usr/local/bin/perl


use strict;
use Getopt::Long;

$| = 1;

my $path     = 'ZFISHFAKE';
my $accessionfile  = undef;

&GetOptions( 'path:s'  => \$path,
             'accessions:s'   => \$accessionfile,
             );

if (!defined($accessionfile) || !defined($path)) {
  die "Missing required args\n";
}


my %contigs;

my $chrid = 1;
open(IN,"<$accessionfile");

my $contignum = 1;
my $clonenum  = 1;
my $dnanum    = 1;
my $chrnum    = 1;



while (<IN>) {
  chomp;

  my $acc = $_;

  open(IN2,"pfetch $acc |");

  my $seq;
  my $found;
  my ($acc,$version);

  while (<IN2>) {

    if (/^>(\S+) (\S+)/) {
      print STDERR "Found title line $1 : $2\n";

      ($acc,$version)  = split(/\./,$2);
     
      $found = 1;
    } else {
      chomp;
      $seq .= $_;
    }
  }

  close(IN2);

  if ($found != 1) {
    print STDERR "ERROR: Can't find accession for $acc\n";
  } else {
    my $len = length($seq);
    
    my $accstart = 1;
    my $accend = $len;
    my $strand = 1;
    my $accver = $acc . "." . $version;

    my $contigid = $acc . "." . $version . "." . $accstart . "." . $accend;

    print "insert into assembly(chromosome_id,chr_start,chr_end,superctg_name,superctg_start,superctg_end,superctg_ori,contig_id,contig_start,contig_end,contig_ori,type) values($chrnum,$accstart,$accend,\'$accver\',$accstart,$accend,1,$contignum,$accstart,$accend,$strand,\'$path\');\n";
    print "insert into clone(clone_id,name,embl_acc,version,embl_version,htg_phase,created,modified) values($clonenum,'$acc','$acc',$version,$version,4,now(),now());\n";
    print "insert into contig(contig_id,name,clone_id,length,embl_offset,dna_id) values($contignum,'$contigid',$clonenum,$len,1,$dnanum);\n";
    
    print "insert into dna(dna_id,sequence,created) values($dnanum,'$seq',now());\n";
    print "insert into chromosome(chromosome_id,name,length) values($chrnum,'$accver',$len);\n";
    
    $contignum++;
    $clonenum++;
    $dnanum++;
    $chrnum++;

  }
}
print "delete from meta where meta_key='assembly.default';\n";
print "insert into meta(meta_value,meta_key) values('assembly.default','ZFISHFAKE');\n";
