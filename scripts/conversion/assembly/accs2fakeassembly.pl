#!/usr/local/bin/perl


use strict;
use Getopt::Long;

$| = 1;

my $chrname  = '1';
my $path     = 'ZFISH_FAKE';
my $accessionfile  = undef;
my $padding  = 10000;

&GetOptions( 'chr:s'   => \$chrname,
             'path:s'  => \$path,
             'accessions:s'   => \$accessionfile,
             'padding:n' => \$padding,
            );

if (!defined($chrname) || !defined($accessionfile) || !defined($path)) {
  die "Missing required args\n";
}


my %contigs;

my $chrid;
if ($chrname =~ /^[0-9]*$/) {
  $chrid = $chrname;
}

my $chrid = 1;
open(IN,"<$accessionfile");

my $contignum = 1;
my $clonenum  = 1;
my $dnanum    = 1;

my $chrstart = 1;


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
    
    
    my $chrend = $chrstart + $len - 1;
    my $accstart = 1;
    my $accend = $len;
    my $strand = 1;

    my $contigid = $acc . "." . $version . "." . $accstart . "." . $accend;

    print "insert into assembly(chromosome_id,chr_start,chr_end,superctg_name,superctg_start,superctg_end,superctg_ori,contig_id,contig_start,contig_end,contig_ori,type) values($chrid,$chrstart,$chrend,\'$chrname\',$chrstart,$chrend,1,$contignum,$accstart,$accend,$strand,\'$path\');\n";
    print "insert into clone(clone_id,name,embl_acc,version,embl_version,htg_phase,created,modified) values($clonenum,'$acc','$acc',$version,$version,4,now(),now());\n";
    print "insert into contig(contig_id,name,clone_id,length,embl_offset,dna_id) values($contignum,'$contigid',$clonenum,$len,1,$dnanum);\n";
    
    print "insert into dna(dna_id,sequence,created) values($dnanum,'$seq',now());\n";
    
    $contignum++;
    $clonenum++;
    $dnanum++;

    $chrstart = $chrstart + $len + $padding;
  }
}
