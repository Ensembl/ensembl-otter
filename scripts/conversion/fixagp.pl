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

#<sequence_fragment>
#  <accession>AL035696.14.1.124034</accession>
#  <chromosome>6</chromosome>
#  <assembly_start>131702</assembly_start>
#  <assembly_end>253735</assembly_end>
#  <fragment_ori>1</fragment_ori>
#  <fragment_offset>2001</fragment_offset>
#</sequence_fragment>

#chr14       415988          582668        5     F       AL512310.3          168774            2094      -
#chr14       582669          719153        6     F       AL391156.3          136600             116      -
#chr14       719154          875145        7     F       AL359218.4          156320             329      -


my $t_host    = 'ecs1d';
my $t_user    = 'ensadmin';
my $t_pass    = 'ensembl';
my $t_port    = 19322;
my $t_dbname  = 'test_otter_chr14';

my $agpfile = undef;
my $tpffile = undef;
my $seqfile = undef;

my $chr      = 14;
my $path     = 'GENOSCOPE';

&GetOptions( 't_host:s'=> \$t_host,
             't_user:s'=> \$t_user,
             't_pass:s'=> \$t_pass,
             't_port:s'=> \$t_port,
             't_dbname:s'  => \$t_dbname,
             'chr:s'     => \$chr,
             'path:s'  => \$path,
             'agp:s'   => \$agpfile,
             'tpf:s'   => \$tpffile,
             'seq:s'   => \$seqfile,
            );

if (!defined($chr) || !defined($agpfile) || !defined($tpffile) || !defined($seqfile)) {
  die "Missing required args\n";
}

my $in  = Bio::SeqIO->new(-file => $seqfile , '-format' => 'Fasta');

my $chrseq = $in->next_seq();

my $tdb = new Bio::EnsEMBL::DBSQL::DBAdaptor(-host => $t_host,
                                             -user => $t_user,
                                             -pass => $t_pass,
                                             -port => $t_port,
                                             -dbname => $t_dbname);


#$tdb->assembly_type($path);
#
#my $slice = $tdb->get_SliceAdaptor()->fetch_by_chr_name("14");
#
#my $seq = $slice->seq;
#$seq =~ s/(.{80})/$1\n/g;
#print $seq . "\n";
#exit;

print "After db connect\n";

open (AGP,"<$agpfile");
open (TPF,"<$tpffile");

my @tpf;
my $count = 0;
while (<TPF>) {
  my @words = split;
  $tpf[$count++] = $words[0];
}


$count = 0; 

my $prev_acc;
my $prev_tpf;
my $ingap = 0;
my $id;
while (<AGP>) {
  chomp;
  $_ =~ s/ //g;

  next if (/^#/);

  my @arr = split(/\t/,$_);
 
  next if ($arr[4] eq "N");

 
  my ($acc,$ver) = split(/\./,$arr[5]);

  if ($acc =~ /\*\*/) {
    print "Rescueing a ** clone\n";
    if ($ingap || $prev_acc == $prev_tpf) {
      #print "$acc = $tpf[$count]\n";
    } else {
      die "WARNING: !!!! Order error at $acc with " .$tpf[$count] . "\n";
    }
    $ingap = 1;

    $id = get_id_from_pfetch($tpf[$count]);

    if ($id eq "no match") {
      die "Failed getting sequence $tpf[$count]\n";
    }
    #print "Versioned id = " . $id . "\n";
  } else {
    if ($ingap) {
      if ($acc ne $tpf[$count]) {
        die "WARNING: !!!! Order error at $acc with " .$tpf[$count] . "\n";
      }
    }
    $ingap = 0;
    $id = $acc . "." . $ver;
  }
  
  my $start = $arr[6];
  my $end   = $arr[7];
  
  if ($end < $start) {
    my $tmp = $end;
    $end = $start;
    $start = $tmp;
  }
  
  my $idstr = $id . "." . $start . "." . $end;
  
  my $ori = -1;
  
  if ($arr[8] eq "+") {
     $ori = 1;
  } 
  
 
  my $rawseq = undef;
  my $acc_nov = $id;
  $acc_nov =~ s/\..*//;

  my $rawseq = run_pfetch($id,"-A -q");
  if ($rawseq !~ /no match/) {
    my ($teststr,$diff) = get_correct_seq($rawseq,$chrseq,$arr[1],$arr[2],
                                          $start,$end,$ori);
    if ($diff) { 
      print "Sequence doesn't match. Trying pfetch without -A and version\n";
      $rawseq = "no match";
    }
  }
  if ($rawseq =~ /no match/) {
    print "Failed getting sequence $id\n";

    my $avail_id = get_id_from_pfetch($acc_nov);

    if ($avail_id !~ /no match/) {

      if ($id ne $avail_id) {
        print "Using different version $avail_id to that in agp $id\n";
      } else {
        print "Secondary pfetch retreived id $avail_id (wanted $id)\n";
      }
      # Change idstr to match the used version
      $idstr = $avail_id . "." . $start . "." . $end;

      $rawseq = run_pfetch($avail_id,"-q");
      if ($rawseq =~ /^no match/) {
        die "pfetch failure suspected\n";
      }
    }
    if ($rawseq =~ /no match/) {
      print "Failed second attempt at getting sequence $acc_nov\n";
    }else {
      my ($teststr,$diff) = get_correct_seq($rawseq,$chrseq,$arr[1],$arr[2],
                                            $start,$end,$ori);
    }
  } 

  if ($rawseq !~ /no match/) {
    chomp $rawseq;
    write_frag($tdb, $chr,$arr[1],$arr[2],$path,
               $idstr,$start,$end,$ori,$chrseq,$rawseq);
  } else {
    print "Not writing $idstr to database\n";
  }

  print "<sequence_fragment>\n";
  print "  <accession>$idstr</accession>\n";
  print "  <chromosome>$chr</chromosome>\n";
  print "  <assembly_start>" . $arr[1] . "</assembly_start>\n";
  print "  <assembly_end>"   . $arr[2] . "</assembly_end>\n";
  print "  <fragment_ori>"   . $ori    . "</fragment_ori>\n";
  print "  <fragment_offset>" . $start . "</fragment_offset>\n";
  print "<sequence_fragment>\n";

  $prev_acc = $acc;
  $prev_tpf = $tpf[$count];

  print "\n====\n";

  $count++;
}

sub get_id_from_pfetch {
  my ($acc) = @_;

  my $idline = run_pfetch($acc,'',1);

  if ($idline eq "no match") { return $idline; }

  my @idwords = split /\s+/,$idline;
  my $id = $idwords[1];

  return $id;
}

# Protect from flaky pfetch server
sub run_pfetch {
  my ($acc,$args,$maxline) = @_;

  my $pcnt = 0;
  my $resstring;
  for ($pcnt=0; $pcnt<5; $pcnt++) {
    $resstring = "";

    my $pstr = "/usr/local/ensembl/bin/pfetch $args $acc |";
    open FPP,$pstr;
    my $resstring = <FPP>;
    if ($resstring =~ "no match") {
      close(FPP);
      next;
    }

    my $linecount = 1;
    while (<FPP> && (!defined($maxline) || $linecount < $maxline)) {
      $resstring .= $_;
      $linecount++;
    }

    close (FPP);
    return $resstring;
  }
  return $resstring;
}

sub write_frag {
  my ($db, $chrname,$chrstart,$chrend,$assembly_type,
      $rawid,$rawstart,$rawend,$ori,$chrseq,$seqstr) = @_;

  my $time = time;
  my $chrid;
  # if db then fetch the chromosome id

  my $chr = $db->get_ChromosomeAdaptor->fetch_by_chr_name($chrname);

  if (!defined($chr)) {
    print STDERR "Storing chromosome $chrname\n";
    my $chrsql = "insert into chromosome(chromosome_id,name) values(null,'$chrname')";
    my $sth    = $db->prepare($chrsql);
    my $res    = $sth->execute;

    $sth = $db->prepare("SELECT last_insert_id()");
    $sth->execute;

    ($chrid) = $sth->fetchrow_array;
    $sth->finish;
  } else {
    print STDERR "Using existing chromosome " . $chr->dbID . "\n";
    $chrid = $chr->dbID;
  }

  print STDERR "Chromosome id $chrid\n";

  my $cloneid = $rawid;
  $cloneid =~ s/\.[0-9]*\.[0-9]*$//;

  print "Clone = " . $cloneid . "\n";

  if ($seqstr) {

  # Find out if the sequence matches the assembly and bandage it if necessary
    my ($correctstr,$diff) = get_correct_seq($seqstr,$chrseq,$chrstart,$chrend,$rawstart,$rawend,$ori);

  # Create clone
    my $clone = new Bio::EnsEMBL::Clone();
    my ($acc,$ver) = split /\./,$cloneid;
    $clone->id($acc);
    $clone->embl_id($acc);
    $clone->version(1);
    $clone->embl_version($ver);
    if ($diff) {
      $clone->htg_phase(-2);
    } else {
      $clone->htg_phase(-1);
    }
    $clone->created($time);
    $clone->modified($time);


    # Create contig
    my $contig = new Bio::EnsEMBL::RawContig;

    $contig->name($rawid);
    $contig->clone($clone);
    $contig->embl_offset(1);
    $contig->length(length($correctstr));

    $contig->seq($correctstr);

    $clone->add_Contig($contig);

    # Now store the clone

    $db->get_CloneAdaptor->store($clone);
  }

  my $contig  = $db->get_RawContigAdaptor->fetch_by_name($rawid);
  my $rawdbid = $contig->dbID;
  my $length  = $contig->length;

  my $sqlstr = "insert into assembly(chromosome_id,chr_start,chr_end,superctg_name,superctg_start,superctg_end,superctg_ori,contig_id,contig_start,contig_end,contig_ori,type) values($chrid,$chrstart,$chrend,\'$rawid\',1,$length,1,$rawdbid,$rawstart,$rawend,$ori,\'$assembly_type\')\n";

  #print "SQL $sqlstr\n";

  my $sth = $db->prepare($sqlstr);
  my $res = $sth->execute;

  $sth->finish;
}

sub get_correct_seq {
  my ($contigstr, $chrseq, $chrstart, $chrend, $rawstart,$rawend,$ori) = @_;

  my $retstr = undef;
  my $isdiff = 0;

  my $chrstr = $chrseq->subseq($chrstart,$chrend);

  my $contigseq = new Bio::Seq(-seq => $contigstr);

  $chrstr = uc $chrstr;

  if ($rawend <= $contigseq->length)  {
    my $contigsubstr = $contigseq->subseq($rawstart,$rawend);
  
    $contigseq = new Bio::Seq(-seq => $contigsubstr);
  
    if ($ori == -1) {
      $contigseq = $contigseq->revcom;
    }
  
    my $chrstrlines = $chrstr;
    $chrstrlines =~ s/(.{80})/$1\n/g;
    $contigsubstr = $contigseq->seq;
    $contigsubstr =~ s/(.{80})/$1\n/g;
    $contigsubstr = uc $contigsubstr;
    # print "Chr = $chrstr\n";
    # print "Contig = " . $contigsubstr . "\n";
    if ($contigsubstr eq $chrstrlines) {
      print "Got match\n";
      $retstr = $contigstr;
    } else {
      my $ndiffline = 0;
      my @chrlines = split /\n/,$chrstrlines;
      my @contiglines = split /\n/,$contigsubstr;
      for (my $linenum = 0; $linenum<scalar(@chrlines); $linenum++) {
        if ($contiglines[$linenum] ne $chrlines[$linenum]) {
          $ndiffline++;
        }
      }
      print "N diff line = $ndiffline N line = " . scalar(@chrlines)."\n";
      if ($ndiffline > 0.95*scalar(@chrlines)) {
#        print "Chr = $chrstr\n";
#        print "Contig = " . $contigsubstr . "\n";
        for (my $linenum = 0; $linenum<scalar(@chrlines); $linenum++) {
          if ($contiglines[$linenum] eq $chrlines[$linenum]) {
            print "Matched line in very different: $contiglines[$linenum]\n";
          }
        }
      }
    }
  } else {
    print "Sequence too short\n";
  }
  if (!defined($retstr)) {
    print "Resorting to padded chromosomal sequence\n";
    my $contigseq = new Bio::Seq(-seq => $chrstr);

    if ($ori == -1) {
      $contigseq = $contigseq->revcom;
    }

    my $padstr = 'N' x ($rawstart-1);

    $retstr = $padstr . $contigseq->seq;
    $isdiff = 1;
  } 
  return ($retstr,$isdiff);
}
