#!/usr/local/bin/perl

use strict;
use Getopt::Long;

use Bio::EnsEMBL::DBSQL::DBAdaptor;


my $s_host    = 'ecs2b';
my $s_user    = 'ensro';
my $s_pass    = '';
my $s_dbname  = 'ens_NCBI_31';
my $s_port    = 3306;

my $t_host    = 'ecs1d';
my $t_user    = 'ensadmin';
my $t_pass    = 'ensembl';
my $t_port    = 19322;
my $t_dbname  = 'otter_chr22_with_anal';

my $chr      = '22';
my $chrstart = 1;
my $chrend   = 100000000;
my $path     = 'NCBI31';

&GetOptions( 's_host:s'    => \$s_host,
             's_user:s'    => \$s_user,
             's_pass:s'    => \$s_pass,
             's_port:s'    => \$s_port,
             's_dbname:s'  => \$s_dbname,
             't_host:s'=> \$t_host,
             't_user:s'=> \$t_user,
             't_pass:s'=> \$t_pass,
             't_port:s'=> \$t_port,
             't_dbname:s'  => \$t_dbname,
             'chr:s'     => \$chr,
             'chrstart:n'=> \$chrstart,
             'chrend:n'  => \$chrend,
             'path:s'  => \$path,
            );



my $sdb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host => $s_host,
					       -user => $s_user,
					       -pass => $s_pass,
					       -port => $s_port,
					       -dbname => $s_dbname);

$sdb->assembly_type($path);

my $tdb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host => $t_host,
					       -user => $t_user,
					       -pass => $t_pass,
					       -port => $t_port,
					       -dbname => $t_dbname);

my $chr_sth = $tdb->prepare( qq {
   select chromosome_id from chromosome 
   where chromosome.name='$chr'
});

$chr_sth->execute;

my $chr_hashref = $chr_sth->fetchrow_hashref;
if (!defined $chr_hashref) {
  die "Couldn't find chromosome $chr in target database\n";
}

my $t_chrid = $chr_hashref->{'chromosome_id'};

print "Target chromosome id = $t_chrid\n";

# First check for duplicate clones used in contigs
my $dup_sth = $sdb->prepare( qq {
  select contig.name from 
         assembly, contig, dna, chromosome 
  where  assembly.chromosome_id=chromosome.chromosome_id and
         chromosome.name='$chr' and 
         contig.contig_id=assembly.contig_id and 
         assembly.chr_start>= $chrstart and
         assembly.chr_end <=$chrend and
         assembly.type = "$path" and
         contig.dna_id=dna.dna_id
  order by chr_start
});
        
$dup_sth->execute;


my %clones;
my %dupclones;
my $ndup = 0;
my $hashref;
while ($hashref = $dup_sth->fetchrow_hashref()) {
  my $contigname = $hashref->{'name'};
  my @bits = split /\./,$contigname;

  my $clone = $bits[0] . "." . $bits[1];

  if (exists($clones{$clone})) {
    print "Duplicate clone "  . $clone . "\n";
    $dupclones{$clone} = 1;
    $ndup++;
  }

  $clones{$clone} = $_;
}



my $sth = $sdb->prepare(qq {
  select chromosome.chromosome_id,
         chr_start,
         chr_end,
         superctg_name,
         superctg_start,
         superctg_end,
         superctg_ori,
         contig.name,
         contig.clone_id,
         contig_start,
         contig_end,
         contig_ori,
         type 
  from assembly,contig,chromosome 
  where assembly.type = "$path" and
        assembly.chromosome_id=chromosome.chromosome_id and
        chromosome.name = '$chr' and
        assembly.chr_start>= $chrstart and
        assembly.chr_end <=$chrend and
        assembly.contig_id = contig.contig_id
  order by chr_start
});
        
$sth->execute;
my $rca = $tdb->get_RawContigAdaptor();

my $t_ca = $tdb->get_CloneAdaptor();
my $s_ca = $sdb->get_CloneAdaptor();

my $hashref;
my $ndiffseq = 0;
my $totfailed = 0;
my $nnotfound = 0;
my $nwritten = 0;
my $ndupcontig = 0;
while ($hashref = $sth->fetchrow_hashref()) {

  my $contigname = $hashref->{'name'};
  my @bits = split /\./,$contigname;

  my $clonename = $bits[0] . "." . $bits[1];

  if (!exists($dupclones{$clonename})) {

    my $contig = $rca->fetch_by_name($hashref->{'name'});
   
    if (!defined($contig)) {
      print STDOUT "Missing contig " . $hashref->{'name'} . " - trying clone\n";
      my $acc = $hashref->{'name'};
      $acc =~ s/\.[0-9]*\.[0-9]*$//;
      my $sth = $tdb->prepare("select name from contig where contig.name like '$acc%'");
      $sth->execute;
      my $hashref2 = $sth->fetchrow_hashref;
      if (defined($hashref2)) {
        print "Looking for $acc did find " . $hashref2->{'name'} . "\n";
      }
      $contig = $rca->fetch_by_name($hashref2->{'name'});
    }

    if (!defined($contig)) {
  
      # Fetch clone from source db
#      my $clone = $s_ca->fetch_by_dbID($hashref->{'clone_id'});
#  
#      foreach my $s_contig (@{$clone->get_all_Contigs}) {
#        my $seq = $s_contig->seq;
#        $s_contig->adaptor($rca);
#        $s_contig->seq($seq);
#      }
#  
#      # Write into target db
#      $clone->adaptor($t_ca);
#  
#      # Now store the clone
#      $t_ca->store($clone);
#  
#      $contig = $rca->fetch_by_name($hashref->{'name'});
    }
  
    if (defined($contig)) {
      my $s_clone = $s_ca->fetch_by_dbID($hashref->{'clone_id'});
      my $s_contig = @{$s_clone->get_all_Contigs}[0];

      my $s_assseq = $s_contig->subseq($hashref->{contig_start},$hashref->{contig_end});
      my $t_assseq = $contig->subseq($hashref->{contig_start},$hashref->{contig_end});
      if ($s_assseq ne $t_assseq) {
	print "start = " . $hashref->{contig_start} . " end " . $hashref->{contig_end} . "\n";
        print "NOTE Contig subseqs sequences different for $clonename\n";
        compare_seqs($s_assseq, $t_assseq);
        $ndiffseq++; 
        $totfailed++;
      } else {

        my $contig_id = $contig->dbID;
        print "Found contig " . $contig->name . "\n";
        my $sth2 = $tdb->prepare( qq:
          insert into assembly(chromosome_id,
                               chr_start,
                               chr_end,
                               superctg_name,
                               superctg_start,
                               superctg_end,
                               superctg_ori,
                               contig_id,
                               contig_start,
                               contig_end,
                               contig_ori,
                               type) 
                       values( 
                           $t_chrid,
                           $hashref->{chr_start},
                           $hashref->{chr_end},
                           "$hashref->{superctg_name}",
                           $hashref->{superctg_start},
                           $hashref->{superctg_end},
                           $hashref->{superctg_ori},
                           $contig_id,
                           $hashref->{contig_start},
                           $hashref->{contig_end},
                           $hashref->{contig_ori},
                           "$hashref->{type}"
                         ):);
        #print $sth2->{Statement} . "\n";
        $sth2->execute;
        $nwritten++;
      }
    } else {
      print "Didn't find " . $hashref->{'name'} . "\n";
      $nnotfound++; 
      $totfailed++;
    } 
  } else {
    print "Clone with multiple contigs $clonename\n";
    $totfailed++;
    $ndupcontig++;
  }
}

print "Number of assembly elements written = $nwritten\n";
print "Total failures = $totfailed\n";
print "No. with different seq = $ndiffseq\n";
print "No. not found in target db = $nnotfound\n";
print "No. of clones with duplicates = " . scalar(keys(%dupclones)) . " (n contig  = $ndupcontig)\n";


sub compare_seqs {
  my ($seq1, $seq2) = @_;

  $seq1 =~ s/(.{80})/$1\n/g;
  $seq2 =~ s/(.{80})/$1\n/g;

  # print "Chr = $chrstr\n";
  # print "Contig = " . $contigsubstr . "\n";

  if ($seq1 ne $seq2) {
    my $ndiffline = 0;
    my @seq2lines = split /\n/,$seq2;
    my @seq1lines = split /\n/,$seq1;
    for (my $linenum = 0; $linenum<scalar(@seq2lines); $linenum++) {
      if ($seq1lines[$linenum] ne $seq2lines[$linenum]) {
        $ndiffline++;
      }
    }
    print "N diff line = $ndiffline N line = " . scalar(@seq2lines)."\n";
    if ($ndiffline > 0.95*scalar(@seq2lines)) {
#        print "Chr = $chrstr\n";
#        print "Contig = " . $seq1 . "\n";
      for (my $linenum = 0; $linenum<scalar(@seq2lines); $linenum++) {
        if ($seq1lines[$linenum] eq $seq2lines[$linenum]) {
          print "Matched line in very different: $seq1lines[$linenum]\n";
        }
      }
    }
  }
}
