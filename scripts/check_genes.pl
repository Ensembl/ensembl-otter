#!/usr/local/bin/perl

# script to process otter or vega database and check for gene problems.

# checks carried out are 1) genes either partially or completely off
# current sequence_set(s) (require realign_offtrack_genes run); 2)
# list duplicate exons (can be resolved with
# remove_duplicate_exons.pl); 3) list other potential problems.

use strict;
use Getopt::Long;
use DBI;
use Sys::Hostname;
use cluster;

# hard wired
my $driver="mysql";
my $port=3306;
my $pass;
my $host='humsrv1';
my $user='ensro';
my $db='otter_human';
my $help;
my $phelp;
my $opt_v;
my $opt_V;
my $opt_D;
my $opt_i='';
my $opt_o='large_transcripts.lis';
my $opt_p='duplicate_exons.lis';
my $opt_q='near_duplicate_exons.lis';
my $opt_r='missing_remarks.lis';
my $cache_file='check_genes.cache';
my $make_cache;
my $opt_c='';
my $opt_s=1000000;
my $opt_t;
my $exclude='GD:';
my $ext;
my $inprogress;
my $vega;
my $set;
my $stats;

$Getopt::Long::ignorecase=0;

GetOptions(
	   'port:s', \$port,
	   'pass:s', \$pass,
	   'host:s', \$host,
	   'user:s', \$user,
	   'db:s', \$db,

	   'help', \$phelp,
	   'h',    \$help,
	   'v',    \$opt_v,
	   'V',    \$opt_V,
	   'D',    \$opt_D,
	   'i:s',  \$opt_i,
	   'o:s',  \$opt_o,
	   'p:s',  \$opt_p,
	   'q:s',  \$opt_q,
	   'r:s',  \$opt_r,
	   'c:s',  \$opt_c,
	   'make_cache',\$make_cache,
	   't:s',  \$opt_t,
	   'exclude:s', \$exclude,
	   'external',  \$ext,
	   'progress',  \$inprogress,
	   'vega',      \$vega,
	   'set:s',     \$set,
	   'stats',     \$stats,
	   );

# help
if($phelp){
  exec('perldoc', $0);
  exit 0;
}
if($help){
  print<<ENDOFTEXT;
check_genes.pl
  -host           char      host of mysql instance ($host)
  -db             char      database ($db)
  -port           num       port ($port)
  -user           char      user ($user)
  -pass           char      passwd

  -h                        this help
  -help                     perldoc help
  -v                        verbose
  -V                        really verbose
  -o              file      output file ($opt_o)
  -p              file      output file ($opt_p)
  -q              file      output file ($opt_q)
  -r              file      output file ($opt_r)
  -c              char      chromosome ($opt_c)
  -make_cache               make cache file
  -exclude                  gene types prefixes to exclude ($exclude)

Select sets (default is vega_sets tagged 'external' + 'internal', E+I)
  -external                 only consider vega_sets tagged as 'external' (E)
  -progress                 also consider vega_sets tagged as 'in progress' (E+I+P)
  -vega                     vega database (all sets in assembly table)
  -set            set       specified set only

  -stats                    calculate stats from cache file only
ENDOFTEXT
    exit 0;
}

# connect
my $dbh;
if(my $err=&_db_connect(\$dbh,$host,$db,$user,$pass)){
  print "failed to connect $err\n";
  exit 0;
}

my $n=0;
if($make_cache){

  # get assemblies of interest
  my %a;
  my %ao;
  my $sth;
  if($set){
    # all assemblies - assume only contains assemblies of interest
    $sth=$dbh->prepare("select a.contig_id, c.name, a.type, a.chr_start, a.chr_end, a.contig_start, a.contig_end, a.contig_ori, cl.embl_acc, cl.embl_version from contig ct, clone cl, chromosome c, assembly a where cl.clone_id=ct.clone_id and ct.contig_id=a.contig_id and a.chromosome_id=c.chromosome_id and a.type=\'$set\'");
  }elsif($vega){
    # all assemblies - assume only contains assemblies of interest
    $sth=$dbh->prepare("select a.contig_id, c.name, a.type, a.chr_start, a.chr_end, a.contig_start, a.contig_end, a.contig_ori, cl.embl_acc, cl.embl_version from contig ct, clone cl, chromosome c, assembly a where cl.clone_id=ct.clone_id and ct.contig_id=a.contig_id and a.chromosome_id=c.chromosome_id");
  }else{
    $sth=$dbh->prepare("select a.contig_id, c.name, a.type, a.chr_start, a.chr_end, a.contig_start, a.contig_end, a.contig_ori, cl.embl_acc, cl.embl_version, vs.vega_type from contig ct, clone cl, chromosome c, assembly a, sequence_set ss left join vega_set vs on (vs.vega_set_id=ss.vega_set_id) where cl.clone_id=ct.clone_id and ct.contig_id=a.contig_id and a.chromosome_id=c.chromosome_id and a.type=ss.assembly_type");
  }
  $sth->execute();
  my $n=0;
  my $no=0;
  while (my @row = $sth->fetchrow_array()){
    my $cid=shift @row;
    my $other;
    if(!$vega){
      my $vega_type=pop @row;
      # consider types:
      if($ext){
	# E only
	if($vega_type ne 'E'){
	  $other=1;
	}
      }elsif($vega_type eq 'N' || $vega_type eq ''){
	# exclude N
	$other=1;
      }elsif($vega_type eq 'P'){
	# exclude P, unless -progress
	if(!$inprogress){
	  $other=1;
	}
      }
    }
    if($other){
      $ao{$cid}=[@row];
      $no++;
    }else{
      # if -vega, all will be stored here
      $a{$cid}=[@row];
      $n++;
    }
  }
  print "$n contigs read from selected assemblies; $no from other assemblies\n";

  # build a list of transcript_info_id's of all transcript remarks
  my %trii;
  my $sth=$dbh->prepare("select transcript_info_id from transcript_remark");
  $sth->execute();
  while (my @row = $sth->fetchrow_array()){
    my($trii)=@row;
    $trii{$trii}++;
  }

  # build list of all contigs, grouped by clone
  # and use to create a2, which points from old or new to current version
  my %a2;
  my %ct;
  {
    my $nn=0;
    my $no=0;
    my $nc=0;
    my $nd=0;
    my $ns=0;
    my %cl;
    my $sth=$dbh->prepare("select cl.embl_acc, cl.embl_version, ct.contig_id, a.type from contig ct, clone cl left join assembly a on (a.contig_id=ct.contig_id) where cl.clone_id=ct.clone_id");
    $sth->execute();
    while (my @row = $sth->fetchrow_array()){
      my($cla,$clv,$cid,$atype)=@row;
      $ct{$cid}=[$cla,$clv,$atype];
      push(@{$cl{$cla}},$cid);
      $nc++;
    }
    # loop over current set of contigs
    # make a subset (a2) of other versions of these clones
    foreach my $cid (keys %a){
      my($cname,$atype)=(@{$a{$cid}});
      if($ct{$cid}){
	my($cla,$clv)=@{$ct{$cid}};
	foreach my $cid2 (@{$cl{$cla}}){
	  if($cid2!=$cid){
	    my($cla2,$clv2,$atype2)=@{$ct{$cid2}};
	    $a2{$cid2}=[$cla2,$clv2,$atype2,$clv,$cid,$cname,$atype];
	    if($clv2<$clv){
	      $no++;
	      print "contig $cid2 is older ($cid)\n" if $opt_V;
	    }else{
	      $nn++;
	      print "contig $cid2 is newer ($cid)\n" if $opt_V;
	    }
	  }else{
	    $ns++;
	  }
	}
      }else{
	print "FATAL: contig $cid not found\n";
	exit 0;
      }
    }
    $nd=$nc-($ns+$no+$nn);
    print "$nc contigs found; $nd different\n";
    print "$ns are current; $no older; $nn newer versions\n";
  }

  my $nexclude=0;
  my %excluded_gsi;
  my %offagp_gsi;
  my %onagp_gsi;
  my %reported_gsi;
  my %reported_gsi_cid;
  my %gsi_a2_clone;
  my %gsi_ao_clone;
  my %gsi_au_clone;
  my %gsi_clone;
  my %type_gsi;
  my %gsi2gn;
  my %missing_tr;
  my $nobs=0;

  # get exons of current genes
  my $sth=$dbh->prepare("select gsi1.stable_id,gn.name,g.type,tsi.stable_id,ti.name,et.rank,e.exon_id,e.contig_id,e.contig_start,e.contig_end,e.sticky_rank,e.contig_strand,e.phase,e.end_phase,cti.transcript_info_id,t.translation_id from exon e, exon_transcript et, transcript t, current_gene_info cgi, gene_stable_id gsi1, gene_name gn, gene g, transcript_stable_id tsi, current_transcript_info cti, transcript_info ti left join gene_stable_id gsi2 on (gsi1.stable_id=gsi2.stable_id and gsi1.version<gsi2.version) where gsi2.stable_id IS NULL and cgi.gene_stable_id=gsi1.stable_id and cgi.gene_info_id=gn.gene_info_id and gsi1.gene_id=g.gene_id and g.gene_id=t.gene_id and t.transcript_id=tsi.transcript_id and tsi.stable_id=cti.transcript_stable_id and cti.transcript_info_id=ti.transcript_info_id and t.transcript_id=et.transcript_id and et.exon_id=e.exon_id and e.contig_id");
  $sth->execute;
  open(OUT,">$cache_file") || die "cannot open cache file $cache_file";
  while (my @row = $sth->fetchrow_array()){
    $n++;

    # transform to chr coords
    my($gsi,$gn,$gt,$tsi,$tn,$erank,$eid,$ecid,$est,$eed,$esr,$es,$ep,$eep,$tiid,$trid)=@row;

    # skip obs genes
    if($gt eq 'obsolete'){
      $nobs++;
      next;
    }

    $gsi2gn{$gsi}="$gn:$gt";

    # look for contig for this exon in selected assembly regions
    if($a{$ecid}){

      my($cname,$atype,$acst,$aced,$ast,$aed,$ao,$cla,$clv)=@{$a{$ecid}};

      # check if exon coordinates are outside AGP
      if($est<$ast || $eed>$aed){
	push(@{$offagp_gsi{$gsi}},join(',',@row));
      }else{
	push(@{$onagp_gsi{$gsi}},join(',',@row));
      }

      my $ecst;
      my $eced;
      if($ao==1){
	# clone is same direction of assembly
	$ecst=$acst+$est-$ast;
	$eced=$acst+$eed-$ast;
      }else{
	# clone is reverse direction of assembly
	$ecst=$aced-$est+$ast;
	$eced=$aced-$eed+$ast;
	# exon orientation is reversed
	$es=-$es;
      }
      # constant direction - easier later
      if($ecst>$eced){
	my $t=$ecst;
	$ecst=$eced;
	$eced=$t;
      }
      my @row2=($gsi,$gn,$gt,$tsi,$tn,$erank,$eid,$ecst,$eced,$cname,$atype,$esr,$es,$ep,$eep,$trid);
      print OUT join("\t",@row2)."\n";

      # record genes with no gene_remark
      if(!$trii{$tiid}){
	$missing_tr{$gt}->{$tsi}="$gsi:$gn";
      }
      
      # record clones that each gsi are attached to and assembly for each gsi
      $gsi_clone{$gsi}->{"$cla.$clv"}=1;
      $type_gsi{"$atype:$cname"}->{$gsi}=1;

    }else{
      $nexclude++;
      push(@{$excluded_gsi{$gsi}},join(',',@row));
      # check other contigs
      if($a2{$ecid}){
	# different version of a contig in $a
	my($cla,$clv,$atype)=@{$a2{$ecid}};
	$gsi_a2_clone{$gsi}->{"$cla.$clv"}=$ecid;
      }elsif($ao{$ecid}){
	# contig in set not selected
	my($cname,$atype,$acst,$aced,$ast,$aed,$ao,$cla,$clv)=@{$ao{$ecid}};
	$gsi_ao_clone{$gsi}->{"$cla.$clv"}=$ecid;
      }elsif($ct{$ecid}){
	# another contig
	my($cla,$clv,$atype)=@{$ct{$ecid}};
	$gsi_au_clone{$gsi}->{"$cla.$clv"}=$ecid;
      }else{
	# an unknown contig
	if(!$reported_gsi_cid{$gsi}->{$ecid}){
	  $reported_gsi_cid{$gsi}->{$ecid}=1;
	  print "WARN: $gsi attached to contig $ecid (unknown)\n" if $opt_v;
	}
      }
    }
    last if ($opt_t && $n>=$opt_t);
  }
  close(OUT);
  $dbh->disconnect();

  # report all genes with missing remarks
  print "Transcripts with missing remarks (see $opt_r):\n";
  open (MOUT,">$opt_r") || die "cannot open remarks file";
  foreach my $gt (sort keys %missing_tr){
    my $n=0;
    my $out='';
    foreach my $tsi (sort keys %{$missing_tr{$gt}}){
      my $gname=$missing_tr{$gt}->{$tsi};
      $n++;
      $out.="  $tsi ($gname)\n";
    }
    print " $n transcripts of gene type $gt have missing remarks\n";
    print MOUT " $n transcripts of gene type $gt have missing remarks:\n$out";
  }
  print "\n";
  close(MOUT);

  my %n_offtrack;

  # report all offtrack genes
  my %orphan_gsi;
  foreach my $type (sort keys %type_gsi){

    # in vega case, chromosome is most useful label
    # in otter case, type is most useful label
    my($atype,$cname)=split(/:/,$type);
    my $label;
    if($vega){
      $label=$type;
    }else{
      $label=$atype;
    }

    $n_offtrack{$label}->[0]=0;
    $n_offtrack{$label}->[1]=0;
    $n_offtrack{$label}->[2]=0;
    print "sequence_set $label\n";

    # report partial genes:
    my %sv;
    foreach my $gsi (sort keys %{$type_gsi{$type}}){
      if($excluded_gsi{$gsi}){
	$orphan_gsi{$gsi}=1;
	# record all sv's that these genes are on in the sequence_set
	foreach my $sv (keys %{$gsi_clone{$gsi}}){
	  if($sv{$sv}){
	    $sv{$sv}.=";$gsi";
	  }else{
	    $sv{$sv}=$gsi;
	  }
	}
	my $gn=$gsi2gn{$gsi};
	print " ERR1 $gsi ($gn) ss=\'$type\' has exon(s) off assembly:\n";
	$n_offtrack{$label}->[0]++;
	# 3 diff classes of clones:
	# V = different version of clone in assembly
	# O = clone in another specified set
	# U = unknown (orphan?) clone
	my $a2c=join(",",(keys %{$gsi_a2_clone{$gsi}}));
	my $aoc=join(",",(keys %{$gsi_ao_clone{$gsi}}));
	my $auc=join(",",(keys %{$gsi_au_clone{$gsi}}));
	if($a2c){$a2c="V:$a2c";}
	if($aoc){$a2c="O:$a2c";}
	if($auc){$a2c="U:$a2c";}
	print "  on clones: $a2c $aoc $auc\n";
	print "   ".join("\n   ",@{$excluded_gsi{$gsi}})."\n" if $opt_v;
      }
    }

    # report the clones in the sequence set, in order, which truncated genes are annotated on
    my $n=0;
    foreach my $cid (sort {$a{$a}->[2]<=>$a{$b}->[2]} keys %a){
      my($cname,$atype2,$acst,$aced,$ast,$aed,$ao,$cla,$clv)=@{$a{$cid}};
      next if $atype ne $atype2;
      $n++;
      my $sv="$cla.$clv";
      if($sv{$sv}){
	my $glist=$sv{$sv};
	print " [$n] $sv [$glist]\n";
      }
    }
    
    # repeat for genes where an exon is on a valid clone, but off AGP
    my %sv2;
    foreach my $gsi (sort keys %{$type_gsi{$type}}){
      if($offagp_gsi{$gsi}){
	foreach my $sv (keys %{$gsi_clone{$gsi}}){
	  if($sv2{$sv}){
	    $sv2{$sv}.=";$gsi";
	  }else{
	    $sv2{$sv}=$gsi;
	  }
	}
	my $gn=$gsi2gn{$gsi};
	$n_offtrack{$label}->[1]++;
	if($onagp_gsi{$gsi}){
	  print " ERR2 $gsi ($gn) ss=\'$atype\' some exon(s) off agp:\n";
	}else{
	  print " ERR2 $gsi ($gn) ss=\'$atype\' all exon(s) off agp:\n";
	}
	print "   ".join("\n   ",@{$offagp_gsi{$gsi}})."\n" if $opt_v;
      }
    }
    my $n=0;
    foreach my $cid (sort {$a{$a}->[2]<=>$a{$b}->[2]} keys %a){
      my($cname,$atype2,$acst,$aced,$ast,$aed,$ao,$cla,$clv)=@{$a{$cid}};
      next if $atype ne $atype2;
      $n++;
      my $sv="$cla.$clv";
      if($sv2{$sv}){
	my $glist=$sv2{$sv};
	print " [$n] $sv [$glist]\n";
      }
    }

  }

  # big problem with orphans - how to tell which elements of assembly
  # are historical?  Partly dealt with by tracking versions...

  foreach my $gsi (sort keys %excluded_gsi){
    # ignore if tagged as not orphan elsewhere
    next if $orphan_gsi{$gsi};
    # ignore unless in another version of clone in current assembly
    next unless $gsi_a2_clone{$gsi};
    my $gn=$gsi2gn{$gsi};
    my %type;
    my %sv;
    foreach my $sv (sort keys %{$gsi_a2_clone{$gsi}}){
      my $cid=$gsi_a2_clone{$gsi}->{$sv};
      my($cla2,$clv2,$atype2,$clv,$cid,$cname,$atype)=@{$a2{$cid}};
      my $type="$atype:$cname";
      $sv{"$cla2.$clv"}=1;
      $type{$type}++;
    }
    foreach my $type (keys %type){
      my($atype,$cname)=split(/:/,$type);
      my $label;
      if($vega){
	$label=$type;
      }else{
	$label=$atype;
      }
      $n_offtrack{$label}->[2]++;
    }
    print " ERR3 $gsi ($gn) linked to =\'".join("\',\'",(keys %type))."\'; clones: ".
	join(",",(keys %sv))."\n";
    # 3 diff classes of clones:
    # V = different version of clone in assembly
    # O = clone in another specified set
    # U = unknown (orphan?) clone
    my $a2c=join(",",(keys %{$gsi_a2_clone{$gsi}}));
    my $aoc=join(",",(keys %{$gsi_ao_clone{$gsi}}));
    my $auc=join(",",(keys %{$gsi_au_clone{$gsi}}));
    if($a2c){$a2c="V:$a2c";}
    if($aoc){$a2c="O:$a2c";}
    if($auc){$a2c="U:$a2c";}
    print "  found on clones: $a2c $aoc $auc\n";
    print "   ".join("\n   ",@{$excluded_gsi{$gsi}})."\n" if $opt_v;
  }

  print "wrote $n records to cache file $cache_file\n";
  print "wrote $nexclude exons ignored as not in selected assembly\n";
  print "skipped $nobs exons marked as obsolete\n";

  print "\nNumber of offtrack gene problems by sequence_set and type (ERR1, ERR2, ERR3)\n";
  foreach my $label (sort keys %n_offtrack){
    printf "%-20s %4d %4d %4d\n",$label,@{$n_offtrack{$label}};
  }

  exit 0;
}

my %gsi;
my %gsi_sum;
my %tsi_sum;
my %atype;
my $n=0;
my $nobs=0;
my $nexclude=0;
my %ngtgnerr;
my %ngtgnerr2;
my %ngtgnerr3;
open(IN,"$cache_file") || die "cannot open $opt_i";
while(<IN>){
  chomp;
  my($gsi,$gn,$gt,$tsi,$tn,$erank,$eid,$ecst,$eced,$cname,$atype,$esr,$es,$ep,$eep,$trid)=split(/\t/);

  # skip obs genes
  if($gt eq 'obsolete'){
    $nobs++;
    next;
  }

  # warn for mislabelled genes
  foreach my $excl (split(/,/,$exclude)){
    if($gt=~/^$excl/ && $gn!~/^$excl/){
      if(!$ngtgnerr2{$gsi}){
	$ngtgnerr2{$gsi}=1;
	print "WARN2 $gsi: type=\'$gt\' but name=\'$gn\'\n" if $opt_v;
      }
    }
  }

  # warn for mislabelled genes/transcripts
  my $gpre='';
  if($gsi=~/^(\w+):/){
    my $gpre=$1;
  }
  my $tpre='';
  if($tsi=~/^(\w+):/){
    my $tpre=$1;
  }
  if($gpre ne $tpre){
    if(!$ngtgnerr3{$tsi}){
      $ngtgnerr3{$tsi}=1;
      print "WARN3 $gsi: $tsi\n";
    }
  }

  my $eflag=0;
  foreach my $excl (split(/,/,$exclude)){
    if($gt=~/^$excl/){
      $nexclude++;
      $eflag=1;
      last;
    }
  }
  next if $eflag;

  # warn for mislabelled genes
  foreach my $excl (split(/,/,$exclude)){
    if($gn=~/^$excl/){
      $eflag=1;
      if(!$ngtgnerr{$gsi}){
	$ngtgnerr{$gsi}=1;
	print "WARN $gsi: type=\'$gt\' but name=\'$gn\'\n" if $opt_v;
      }
    }
  }
  next if $eflag;

  # expect transcripts to stay on same assembly
  if($tsi_sum{$tsi}){
    my($tn2,$cname2,$atype2)=@{$tsi_sum{$tsi}};
    if($cname2 ne $cname){
      print "ERR: $gsi ($gn): $tsi ($tn) on chr $cname and $cname2\n";
    }elsif($atype ne $atype2){
      print "ERR: $gsi ($gn): $tsi ($tn) on chr $atype and $atype2\n";
    }
  }else{
    $tsi_sum{$tsi}=[$tn,$cname,$atype];
  }

  push(@{$gsi{$atype}->{$gsi}},[$tsi,$erank,$eid,$ecst,$eced,$esr,$es,$ep,$eep,$trid]);

  # these relationships should be fixed
  $atype{$atype}=$cname;
  $gsi_sum{$gsi}=[$gn,$gt];

  $n++;
}
close(IN);
print scalar(keys %gsi_sum)." genes read; $nobs obsolete skipped; $nexclude excluded\n";
print "$n name relationships read\n\n";
print scalar(keys %ngtgnerr)." naming errors (GD:name; type)\n";
print scalar(keys %ngtgnerr2)." naming errors (name; GD:type\n";

# another option for script, to use cache file to generate gene count stats
if($stats){
  my %stats;
  foreach my $atype (keys %gsi){
    my $cname=$atype{$atype};
    foreach my $gsi (keys %{$gsi{$atype}}){
      my($gn,$gt)=@{$gsi_sum{$gsi}};
      foreach my $set ($atype,'All'){
	foreach my $type ($gt,'All'){
	  # count genes
	  $stats{$set}->{$type}->[0]++;
	  my %t;
	  my %e;
	  foreach my $re (@{$gsi{$atype}->{$gsi}}){
	    my($tsi,$erank,$eid)=@$re;
	    $t{$tsi}++;
	    $e{$eid}++;
	    # number of exons
	    $stats{$set}->{$type}->[2]++;
	  }
	  # number of transcripts
	  $stats{$set}->{$type}->[1]+=scalar(keys %t);
	  # number of unique exons
	  $stats{$set}->{$type}->[3]+=scalar(keys %e);
	}
      }
    }
  }
  $atype{'All'}='All';
  foreach my $atype (sort keys %stats){
    my $cname=$atype{$atype};
    foreach my $type (sort keys %{$stats{$atype}}){
      printf "%-20s %-25s %6d %6d %6d %6d\n",
      "$atype ($cname)",$type,@{$stats{$atype}->{$type}};
    }
  }
  exit 0;
}

# get clones from assemblies of interest
my %a;
my $sth;
if($vega){
  $sth=$dbh->prepare("select a.type, cl.embl_acc, a.chr_start, a.chr_end, cl.name from clone cl, contig ct, assembly a where a.contig_id=ct.contig_id and ct.clone_id=cl.clone_id");
}else{
  $sth=$dbh->prepare("select a.type, cl.embl_acc, a.chr_start, a.chr_end, cl.name from clone cl, contig ct, assembly a, sequence_set ss, vega_set vs where a.contig_id=ct.contig_id and ct.clone_id=cl.clone_id and a.type=ss.assembly_type and ss.vega_set_id=vs.vega_set_id and vs.vega_type != 'N'");
}
$sth->execute;
my $n=0;
while (my @row = $sth->fetchrow_array()){
  my $type=shift @row;
  my $embl_acc=shift @row;
  $a{$type}->{$embl_acc}=[@row];
  $n++;
  }
print "$n contigs read from assembly\n";

my $nsticky=0;
my $nexon=0;
my %dup_exon;
my $nmc=0;
my $nmcb=0;
my $nl=0;
my $flag_v;
my $nip=0;
my $npntr=0;
my %t2e;
my %e2t;
my %e;
my %elink;
my %eall;
my %e2g;
open(OUT,">$opt_o") || die "cannot open $opt_o";
open(OUT2,">$opt_p") || die "cannot open $opt_p";
open(OUT3,">$opt_q") || die "cannot open $opt_q";
foreach my $atype (keys %gsi){
  my $cname=$atype{$atype};
  print "Checking \'$atype\' (chr \'$cname\')\n";
  foreach my $gsi (keys %{$gsi{$atype}}){

    # debug:
    if($gsi eq 'OTTHUMG00000032751' && $opt_D){
      $flag_v=1;
      print "debug mode\n";
    }else{
      $flag_v=0;
    }
    
    my($gn,$gt)=@{$gsi_sum{$gsi}};
    my %eids;
    my %eidso;
    # look for overlapping exons and group exons into transcripts
    # (one gene at a time)
    foreach my $rt (sort {
                          $a->[0]<=>$b->[0] || 
                          $a->[1]<=>$b->[1] || 
                          $a->[5]<=>$b->[5]
			    } @{$gsi{$atype}->{$gsi}}){
      my($tsi,$erank,$eid,$ecst,$eced,$esr,$es,$ep,$eep,$trid)=@{$rt};
      if($e{$gsi}->{$eid}){
	# either stored as sticky rank2 or this is sticky rank2
	if($eids{$eid} || $esr>1){

	  my($st,$ed,$es,$ep,$eep,$trid)=@{$e{$gsi}->{$eid}};

	  # save originals
	  my $esro=1;
	  if($eids{$eid}){
	    $esro=$eids{$eid};
	  }

	  # skip if identical match to old original
	  my $match;
	  foreach my $esr2 (keys %{$eidso{$eid}}){
	    my($st2,$ed2)=@{$eidso{$eid}->{$esr2}};
	    if($st2==$ecst && $ed2==$eced){
	      $match=1;
	    }
	  }

	  # save original before modify so don't check twice
	  $eidso{$eid}->{$esro}=[$st,$ed] unless $eidso{$eid}->{$esro};
	  $eidso{$eid}->{$esr}=[$ecst,$eced] unless $eidso{$eid}->{$esr};
	  $eids{$eid}=1;

	  if($match){
	    # if identical, check for sticky
	  }elsif($ed+1==$ecst){
	    $eids{"$eid.$esr"}=[$ecst,$eced];
	    $ed=$eced;
	    $e{$gsi}->{$eid}=[$st,$ed,$es,$ep,$eep,$trid];
	    $nsticky++;
	  }elsif($eced+1==$st){
	    $st=$ecst;
	    $e{$gsi}->{$eid}=[$st,$ed,$es,$ep,$eep,$trid];
	    $nsticky++;
	  }else{
	    print "ERR: duplicate exon id $eid, but no sticky alignment\n";
	  }
	}
      }else{
	my $flag;
	# compare current exon to all existing ones...
	foreach my $eid2 (keys %{$e{$gsi}}){
	  my($st,$ed,$es2,$ep2,$eep2,$trid2)=@{$e{$gsi}->{$eid2}};
	  if($st==$ecst && $ed==$eced){
	    # duplicate exons
	    if($es!=$es2){
	      print OUT3 "NON-DUP: $eid, $eid2 identical but on opposite strands!\n";
	    }elsif($ep!=$ep2){
	      print OUT3 "NON-DUP: $eid, $eid2 identical but on diff phases ($ep,$ep2)\n";
	    }elsif($eep!=$eep2){
	      print OUT3 "WARN NON-DUP: $eid, $eid2 identical but diff end phases ($eep,$eep2) [$ep,$ep2]\n";
	    }elsif($dup_exon{$eid}==$eid2 || $dup_exon{$eid2}==$eid){
	      # don't report again
	    }else{
	      $dup_exon{$eid}=$eid2;
	      print OUT2 "$eid\t$eid2\t$st\t$ed\n";
	    }
	    $flag=1;
	    $eid=$eid2;
	  }else{
	    my $mxst=$st;
	    $mxst=$ecst if $ecst>$mxst;
	    my $mied=$ed;
	    $mied=$eced if $eced<$mied;
	    if($mxst<=$mied){
	      push(@{$elink{$gsi}->{$eid}},$eid2);
	    }
	  }
	}
	if(!$flag){
	  # check for phase consistency and warn
	  # if trid==0; $ep=$eep=-1; else either $ep=$eep=-1 or any positive
	  my $flag_noncoding=0;
	  if($ep==-1 || $eep==-1){
	    $flag_noncoding=1 if $ep==-1;
	    if($ep+$eep==-2){
	      print OUT3 "ERR1 $eid $ep $eep inconsistent noncoding phases\n";
	      $nip++;
	    }
	  }
	  if($trid==0 && $flag_noncoding==0){
	    print OUT3 "ERR2 $eid $ep $eep exon has phase when no translation\n";
	    $npntr++;
	  }
	  $e{$gsi}->{$eid}=[$ecst,$eced,$es,$ep,$eep,$trid];
	  push(@{$eall{$ecst}->{$eced}},$eid);
	  $eids{$eid}=$esr if $esr>1;
	  $nexon++;
	}
      }
      push(@{$t2e{$gsi}->{$tsi}},$eid);
      push(@{$e2t{$gsi}->{$eid}},$tsi);
      if($e2g{$eid} && $e2g{$eid} ne $gsi){
	# eids should only be part of a single gid
	print "FATAL $eid part of $gsi and $e2g{$eid}\n";
      }else{
	$e2g{$eid}=$gsi;
      }
    }

    # get size of transcripts and warn of large ones
    my %tse;
    foreach my $tsi (keys %{$t2e{$gsi}}){
      my $mist=1000000000000;
      my $mxed=-1000000000000;
      foreach my $eid (@{$t2e{$gsi}->{$tsi}}){
	my($st,$ed)=@{$e{$gsi}->{$eid}};
	$mist=$st if $st<$mist;
	$mxed=$ed if $ed>$mxed;
      }
      $tse{$tsi}=[$mist,$mxed];
      my $tsize=$mxed-$mist;
      if($tsize>$opt_s){
	my($tn)=@{$tsi_sum{$tsi}};
	print OUT "WARN $tsize is size of $tsi ($tn), $gsi ($gn,$gt)\n";
	$nl++;
      }
    }
    my $cl=new cluster();
    # link exons by transcripts
    foreach my $tsi (keys %{$t2e{$gsi}}){
      $cl->link([@{$t2e{$gsi}->{$tsi}}]);
      print "D: $tsi ".join(',',@{$t2e{$gsi}->{$tsi}})."\n" if $flag_v;
    }
    # link exons by overlap
    foreach my $eid (keys %{$elink{$gsi}}){
      $cl->link([$eid,@{$elink{$gsi}->{$eid}}]);
      print "D: $eid ".join(',',@{$elink{$gsi}->{$eid}})."\n" if $flag_v;
    }
    if($cl->cluster_count>1){
      print "$gsi ($gt,$gn) has multiple clusters\n";

      # analysis by overlap of exons
      my $ncid=0;
      foreach my $cid ($cl->cluster_ids){
	$ncid++;
	my %tcl;
	foreach my $eid ($cl->cluster_members($cid)){
	  foreach my $tsi (@{$e2t{$gsi}->{$eid}}){
	    $tcl{$tsi}++;
	  }
	}
	print " Cluster $ncid: ".join(',',(keys %tcl))."\n";
      }

      # analysis by overlap of transcripts
      my $last_ed;
      foreach my $tsi (sort {$tse{$a}->[0]<=>$tse{$b}->[0]} keys %tse){
	my($st,$ed)=@{$tse{$tsi}};
	my($tn)=@{$tsi_sum{$tsi}};
	if($last_ed && $last_ed<$st){
	  my $gap=$st-$last_ed;
	  print "  **GAP of $gap bases\n";
	  my $nc=0;
	  my $out='';
	  foreach my $embl_acc (keys %{$a{$atype}}){
	    my($st2,$ed2,$name)=@{$a{$atype}->{$embl_acc}};
	    if($st2>=$last_ed && $st2<=$st){
	      $nc++;
	      $out.="    Boundary of $embl_acc ($name)\n";
	    }
	    if($ed2>=$last_ed && $ed2<=$st){
	      $nc++;
	      $out.="    Boundary of $embl_acc ($name)\n";
	    }
	  }
	  if($nc<=2){
	    print $out;
	    $nmcb++;
	  }
	}
	print "  $tsi ($tn): $st-$ed\n";
	$last_ed=$ed;
      }
      $nmc++;
    }
  }
}
print scalar(keys %dup_exon)." duplicate exons\n";
print "$nmc genes with non overlapping transcripts; $nmcb cases gap crosses single clone boudary\n";
print "found $nexon exons; $nsticky sticky exons\n";
print "$nip exons have inconsistent noncoding phases; $npntr exons have phase when no translation\n";
print "$nl large transcripts found (see $opt_o)\n\n";
close(OUT);
close(OUT2);
close(OUT3);

# global check on duplicate exons - look for cases where exact duplicate exons are part of different genes
my $dgcl=new cluster();
# need to keep a list of exons that are involved in pairs
my %dg2s;
my @s2e;
my $is2e=0;
foreach my $ecst (keys %eall){
  foreach my $eced (keys %{$eall{$ecst}}){
    if(scalar(@{$eall{$ecst}->{$eced}})>1){
      # multiple exons share these coordinates (however could be just different phases...so count distinct genes)
      my %gsi;
      foreach my $eid (@{$eall{$ecst}->{$eced}}){
	$gsi{$e2g{$eid}}++;
      }
      if(scalar(keys %gsi)>1){
	$dgcl->link([(keys %gsi)]);
	$s2e[$is2e]=[@{$eall{$ecst}->{$eced}}];
	foreach my $gsi (keys %gsi){
	  push(@{$dg2s{$gsi}},$is2e);
	}
	$is2e++;
      }
    }
  }
}
my $ngcl=$dgcl->cluster_count;
if($ngcl>1){
  print "$ngcl clusters of genes that share identical exons\n";
  # analysis by cluster
  my $igcl=0;
  foreach my $cid ($dgcl->cluster_ids){
    $igcl++;
    my @gsi=$dgcl->cluster_members($cid);

    # for each gene cluster, identify transcripts involved and how they are linked
    my $tcl=new cluster();
    my %is2e;
    my %e2s;
    foreach my $gsi (@gsi){
      foreach my $is2e (@{$dg2s{$gsi}}){
	$is2e{$is2e}++;
      }
    }
    foreach my $is2e (keys %is2e){
      my %tsi;
      foreach my $eid (@{$s2e[$is2e]}){
	$e2s{$eid}=$is2e;
	foreach my $gsi (@gsi){
	  foreach my $tsi (@{$e2t{$gsi}->{$eid}}){
	    $tsi{$tsi}++;
	  }
	}
      }
      $tcl->link([(keys %tsi)]);
    }
    my @ctsi=$tcl->cluster_ids;
    print " Cluster $igcl: ".scalar(@gsi)." genes; ".scalar(@ctsi)." sets of duplicated transcripts\n";

    my $itcl=0;
    foreach my $tcid (@ctsi){
      $itcl++;
      my @tsi=$tcl->cluster_members($tcid);
      print "  Transcript set $itcl: ".scalar(@tsi)." transcripts\n";
      my %tsi=map{$_,1}@tsi;
      my %gset;
      my %tset;
      foreach my $gsi (sort @gsi){
	my @gtsi=(keys %{$t2e{$gsi}});
	my $nt=scalar(@gtsi);
	my $ntd=0;
	foreach my $tsi (@gtsi){
	  if($tsi{$tsi}){
	    $ntd++;
	  }
	}
	$gset{$gsi}=[$ntd,$nt];
	foreach my $tsi (sort @gtsi){
	  if($tsi{$tsi}){
	    my @e=@{$t2e{$gsi}->{$tsi}};
	    my $ne=scalar(@e);
	    my $ned=0;
	    my @eo;
	    foreach my $eid (@e){
	      my $i=0;
	      if($e2s{$eid}){
		$i=$e2s{$eid};
		$ned++;
	      }
	      push(@eo,$i);
	    }
	    $tset{$gsi}->{$tsi}=[$ned,$ne,@eo];
	  }
	}
      }
      # space and order
      my %id;
      foreach my $gsi (@gsi){
	foreach my $tsi (keys %{$tset{$gsi}}){
	  my($ned,$ne,@eo)=@{$tset{$gsi}->{$tsi}};
	  for(my $i=0;$i<scalar(@eo);$i++){
	    if($eo[$i]>0){
	      $id{$eo[$i]}->[0]+=$i;
	      $id{$eo[$i]}->[1]++;
	    }
	  }
	}
      }
      foreach my $id (keys %id){
	my($s,$n)=@{$id{$id}};
	$id{$id}=$s/$n;
      }
      my $i=1;
      foreach my $id (sort {$id{$a}<=>$id{$b}} keys %id){
	$id{$id}=$i;
	$i++;
      }
      # output
      foreach my $gsi (sort @gsi){
	my($ntd,$nt)=@{$gset{$gsi}};
	print "  $gsi ($ntd/$nt):\n";
	foreach my $tsi (sort keys %{$tset{$gsi}}){
	  my($ned,$ne,@eo)=@{$tset{$gsi}->{$tsi}};
	  for($i=0;$i<scalar(@eo);$i++){
	    if($eo[$i]>0){
	      $eo[$i]=$id{$eo[$i]};
	    }
	  }
	  print "    $tsi ($ned/$ne): ".join(' ',@eo)."\n";
	}
      }
    }
  }
}
print "\n";

# new check - for each transcript, check all exons are sequential, same strand
# sensible direction etc.  Check orientation of all transcripts in a gene consistent
my $neo=0;
my $ned=0;
my $ntd=0;
foreach my $atype (keys %gsi){
  my $cname=$atype{$atype};
  foreach my $gsi (keys %{$gsi{$atype}}){
    my($gn,$gt)=@{$gsi_sum{$gsi}};
    # structure data
    my %tsi;
    foreach my $re (@{$gsi{$atype}->{$gsi}}){
      my($tsi,$erank,$eid,$ecst,$eced,$esr,$es,$ep,$eep)=@$re;
      $erank--;
      # id, st, ed, esr, strand, phase, endphase
      if($tsi{$tsi}->[$erank]){
	# assume merging a sticky...
	my($eid2,$ecst2,$eced2,$esr2,$es2,$ep2,$eep2)=@{$tsi{$tsi}->[$erank]};
	if($esr==2 || $esr2==2){
	  my $esr3;
	  if($esr==1 || $esr2==1){
	    # 1,2=>1
	    $esr3=1;
	  }else{
	    # 2,3=>2
	    $esr3=2;
	  }
	  if($eced+1==$ecst2){
	    $eced=$eced2;
	  }elsif($eced2+1==$ecst){
	    $ecst=$ecst2;
	  }else{
	    print "FATAL: cannot merge sticky exons $tsi: $eid:$ecst-$eced, $eid2:$ecst2-$eced2\n";
	  }
	  $tsi{$tsi}->[$erank]=[$eid,$ecst,$eced,$esr3,$es,$ep,$eep];
	}else{
	  print "FATAL: Duplicate rank for $tsi, $erank\n";
	}
      }else{
	$tsi{$tsi}->[$erank]=[$eid,$ecst,$eced,$esr,$es,$ep,$eep];
      }
    }
    my $dirg=0;
    foreach my $tsi (keys %tsi){
      my $last;
      my $dirt=0;
      for(my $i=0;$i<scalar(@{$tsi{$tsi}});$i++){
	my($eid,$ecst,$eced,$esr,$es,$ep,$eep)=@{$tsi{$tsi}->[$i]};
	my $erank=$i+1;
	print "WARN $tsi: unresolved sticky in $eid $esr\n" if $esr>1;

	# check consistent direction
	if($dirt){
	  if($es!=$dirt){
	    print "ERR: $tsi direction is $dirt, but exon $eid is $es\n";
	    $ned++;
	    next;
	  }
	}else{
	  $dirt=$es;
	}

	# check order in sequence
	if($dirt==1){
	  if($last){
	    if($last>=$ecst){
	      print "ERR: $gsi $tsi exon $erank ($eid) out of order $ecst-$eced follows $last ($dirt)\n";
	      $neo++;
	    }else{
	      $last=$eced;
	    }
	  }else{
	    $last=$eced;
	  }
	}else{
	  if($last){
	    if($last<=$eced){
	      print "ERR: $gsi $tsi exon $erank ($eid) out of order $ecst-$eced follows $last ($dirt)\n";
	      $neo++;
	    }else{
	      $last=$ecst;
	    }
	  }else{
	    $last=$ecst;
	  }
	}

      }

      if($dirg){
	if($dirt!=$dirg){
	  print "ERR: $gsi has direction $dirg, but $tsi has direction $dirt\n";
	  $ntd++;
	}
      }else{
	$dirg=$dirt;
      }

    }
  }
}
print "$neo exons are out of order; $ned exons have inconsistent direction\n";
print "$ntd transcripts have inconsistent direction\n";

print "\nEND check_genes.pl\n";

exit 0;

# connect to db with error handling
sub _db_connect{
  my($rdbh,$host,$database,$user,$pass)=@_;
  my $dsn = "DBI:$driver:database=$database;host=$host;port=$port";
  
  # try to connect to database
  eval{
    $$rdbh = DBI->connect($dsn, $user, $pass,
			  { RaiseError => 1, PrintError => 0 });
  };
  if($@){
    print "$database not on $host\n$@\n" if $opt_v;
    return -2;
  }
}

__END__


=pod

=head1 rename_genes.pl

=head1 DESCRIPTION

=head1 EXAMPLES

=head1 FLAGS

=over 4

=item -h

Displays short help

=item -help

Displays this help message

=back

=head1 VERSION HISTORY

=over 4

=item 17-MAR-2004

B<th> released first version

=back

=head1 BUGS

=head1 AUTHOR

B<Tim Hubbard> Email th@sanger.ac.uk

=cut
