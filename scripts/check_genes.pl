#!/usr/bin/env perl

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
my $opt_O='check_genes_log.out';
my $opt_p='duplicate_exons.lis';
my $opt_q='near_duplicate_exons.lis';
my $opt_r='missing_remarks.lis';
my $opt_R='missing_descriptions.lis';
my $cache_file='check_genes.cache';
my $make_cache;
my $read_cache;
my $opt_c='';
my $opt_s=1000000;
my $opt_t;
my $exclude='GD';
my $exclude_all;
my $ext;
my $inprogress;
my $vega;
my $set;
my $anno;
my $stats;
my $ccds;
my $ccds_stop;
my $ccds_list;
my $opt_k;
my $report_ok_seleno;
my $report_only;
my $opt_n;
my $ccds_id;

$|=1;

my $ncheck;

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
	   'O:s',  \$opt_O,
	   'p:s',  \$opt_p,
	   'q:s',  \$opt_q,
	   'r:s',  \$opt_r,
	   'R:s',  \$opt_R,
	   'c:s',  \$opt_c,
	   'make_cache',\$make_cache,
	   'read_cache',\$read_cache,
	   't:s',  \$opt_t,
	   'exclude:s', \$exclude,
	   'exclude_all', \$exclude_all,
	   'external',  \$ext,
	   'progress',  \$inprogress,
	   'vega',      \$vega,
	   'set:s',     \$set,
	   'anno',      \$anno,
	   'stats',     \$stats,
	   'ccds',      \$ccds,
	   'ccds_stop', \$ccds_stop,
	   'ccds_id:s', \$ccds_id,
	   'ccds_list:s',\$ccds_list,
	   'k:s',       \$opt_k,
	   'report_ok_seleno', \$report_ok_seleno,
	   'report_only:s', \$report_only,
	   'n:s',       \$opt_n,
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
  -O              file      report file ($opt_O)
  -o              file      output file ($opt_o)
  -p              file      output file ($opt_p)
  -q              file      output file ($opt_q)
  -r              file      output file ($opt_r)
  -R              file      output file ($opt_R)
  -c              char      chromosome ($opt_c)
  -make_cache               make cache file
  -read_cache               read cache file
  -exclude        PRE[,PRE] gene types prefixes to exclude ($exclude)
  -exclude_all              exclude all gene types prefixes

Select sets (default is vega_sets tagged 'external' + 'internal', E+I)
  -external                 only consider vega_sets tagged as 'external' (E)
  -progress                 also consider vega_sets tagged as 'in progress' (E+I+P)
  -vega                     vega database (all sets in assembly table)
  -anno                     clones marked as 'annotated' only
  -set            set       specified set only

  -stats                    calculate stats from cache file only

  -k              file      read bad translations log file (to merge in output)

  -report_only    num[,num] restrict types of analysis by number
ENDOFTEXT
    exit 0;
}

my %report_only;
%report_only=map{$_,1}split(/,/,$report_only);
my %exclude;
%exclude=map{$_,1}split(/,/,$exclude);

# connect
my $dbh;
my $flag_no_db;
if(my $err=&_db_connect(\$dbh,$host,$db,$user,$pass)){
  if($read_cache){
    $flag_no_db=1;
  }else{
    print "failed to connect $err\n";
    exit 0;
  }
}

open(LOG,">$opt_O") || die "cannot open $opt_O";

if($opt_k){
  if(open(IN,"$opt_k")){
    close(IN);
  }else{
    my $out="ERROR: cannot open $opt_k\n";
    print LOG $out;
    print $out;
    exit 0;
  }
}

$ncheck++;
print "gene_check report\n\n";
my @data;
if($read_cache){
  open(IN,"$cache_file") || die "cannot open $opt_i";
  while(<IN>){
    chomp;
    push(@data,[split(/\t/)]);
  }
  if(!$stats && (!$report_only || $report_only{$ncheck})){
    print "[$ncheck] Genes with missing descriptions - NOT CHECKED because -read_cache\n\n";
  }

}else{
  my $n=0;

  print LOG "START assembly processing\n\n";

  # get assemblies of interest
  my %a;
  my %ao;
  my $sth;
  if($set){
    if($anno){
      # all assemblies - assume only contains assemblies of interest
      $sth=$dbh->prepare("select a.contig_id, c.name, a.type, a.chr_start, a.chr_end, a.contig_start, a.contig_end, a.contig_ori, cl.embl_acc, cl.embl_version from contig ct, clone cl, chromosome c, assembly a, current_clone_info cci, clone_remark cr where cl.clone_id=ct.clone_id and ct.contig_id=a.contig_id and a.chromosome_id=c.chromosome_id and a.type=\'$set\' and cl.clone_id=cci.clone_id and cci.clone_info_id=cr.clone_info_id and cr.remark rlike '^Annotation_remark-[[:blank:]]*annotated'");
    }else{
      $sth=$dbh->prepare("select a.contig_id, c.name, a.type, a.chr_start, a.chr_end, a.contig_start, a.contig_end, a.contig_ori, cl.embl_acc, cl.embl_version from contig ct, clone cl, chromosome c, assembly a where cl.clone_id=ct.clone_id and ct.contig_id=a.contig_id and a.chromosome_id=c.chromosome_id and a.type=\'$set\'");
    }
  }elsif($vega){
    # all assemblies - assume only contains assemblies of interest
    $sth=$dbh->prepare("select a.contig_id, c.name, a.type, a.chr_start, a.chr_end, a.contig_start, a.contig_end, a.contig_ori, cl.embl_acc, cl.embl_version from contig ct, clone cl, chromosome c, assembly a where cl.clone_id=ct.clone_id and ct.contig_id=a.contig_id and a.chromosome_id=c.chromosome_id");
  }elsif($anno){
    $sth=$dbh->prepare(q{
    SELECT a.contig_id
      , c.name
      , a.type
      , a.chr_start
      , a.chr_end
      , a.contig_start
      , a.contig_end
      , a.contig_ori
      , cl.embl_acc
      , cl.embl_version
      , vs.vega_type
    FROM (contig ct
      , clone cl
      , chromosome c
      , assembly a
      , sequence_set ss
      , current_clone_info cci
      , clone_remark cr)
    LEFT JOIN vega_set vs
      ON (vs.vega_set_id = ss.vega_set_id)
    WHERE cl.clone_id = ct.clone_id
      AND ct.contig_id = a.contig_id
      AND a.chromosome_id = c.chromosome_id
      AND a.type = ss.assembly_type
      AND cl.clone_id = cci.clone_id
      AND cci.clone_info_id = cr.clone_info_id
      AND cr.remark rlike '^Annotation_remark-[[:blank:]]*annotated'
    });
  }else{
    $sth=$dbh->prepare(q{
        SELECT a.contig_id
          , c.name
          , a.type
          , a.chr_start
          , a.chr_end
          , a.contig_start
          , a.contig_end
          , a.contig_ori
          , cl.embl_acc
          , cl.embl_version
          , vs.vega_type
        FROM (contig ct
          , clone cl
          , chromosome c
          , assembly a
          , sequence_set ss)
        LEFT JOIN vega_set vs
          ON (vs.vega_set_id = ss.vega_set_id)
        WHERE cl.clone_id = ct.clone_id
          AND ct.contig_id = a.contig_id
          AND a.chromosome_id = c.chromosome_id
          AND a.type = ss.assembly_type
        });
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
  print LOG "$n contigs read from selected assemblies; $no from other assemblies\n";

  # build a list of all gene_descriptions (not keeping gene_id so map to gene_stable_id)
  my %gdes;
  {
    my $sth=$dbh->prepare("select gsi.stable_id from gene_stable_id gsi, gene_description gd where gsi.gene_id=gd.gene_id");
    $sth->execute();
    while (my ($gsi) = $sth->fetchrow_array()){
      $gdes{$gsi}++;
    }
  }

  # build a list of transcript_info_id's of all transcript remarks
  my %trii;
  {
    my $sth=$dbh->prepare("select transcript_info_id from transcript_remark");
    $sth->execute();
    while (my @row = $sth->fetchrow_array()){
      my($trii)=@row;
      $trii{$trii}++;
    }
  }

  # build a list of translations
  my %tle;
  {
    my $sth=$dbh->prepare("select * from translation");
    $sth->execute();
    while (my @row = $sth->fetchrow_array()){
      my($tlid,$est,$estid,$eed,$eedid)=@row;
      $tle{$tlid}=[$est,$estid,$eed,$eedid];
    }
  }

  # build list of currently editable 'visible' sequence sets
  my %vss;
  {
    my $sth=$dbh->prepare("select assembly_type,hide from sequence_set");
    $sth->execute();
    while (my @row = $sth->fetchrow_array()){
      my($type,$hide)=@row;
      $vss{$type}=$hide;
    }
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
    my $sth=$dbh->prepare(q{
        SELECT cl.embl_acc
          , cl.embl_version
          , ct.contig_id
          , a.type
        FROM (contig ct
          , clone cl)
        LEFT JOIN assembly a
          ON (a.contig_id = ct.contig_id)
        WHERE cl.clone_id = ct.clone_id
        });
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
	      print LOG "contig $cid2 is older ($cid)\n" if $opt_V;
	    }else{
	      $nn++;
	      print LOG "contig $cid2 is newer ($cid)\n" if $opt_V;
	    }
	  }else{
	    $ns++;
	  }
	}
      }else{
	print LOG "FATAL: contig $cid not found\n";
	exit 0;
      }
    }
    $nd=$nc-($ns+$no+$nn);
    print LOG "$nc contigs found; $nd different\n";
    print LOG "$ns are current; $no older; $nn newer versions\n";
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
  my %missing_gdes;
  my $nobs=0;

  # get exons of current genes
  my $sth=$dbh->prepare(q{
    SELECT gsi1.stable_id,gn.name,g.type,tsi.stable_id,ti.name,et.rank,e.exon_id,e.contig_id,e.contig_start,e.contig_end,e.sticky_rank,e.contig_strand,e.phase,e.end_phase,cti.transcript_info_id,t.translation_id
    FROM (exon e
      , exon_transcript et
      , transcript t
      , current_gene_info cgi
      , gene_stable_id gsi1
      , gene_name gn
      , gene g
      , transcript_stable_id tsi
      , current_transcript_info cti
      , transcript_info ti)
    LEFT JOIN gene_stable_id gsi2
      ON (gsi1.stable_id = gsi2.stable_id
          AND gsi1.version < gsi2.version)
    WHERE gsi2.stable_id IS NULL
      AND cgi.gene_stable_id = gsi1.stable_id
      AND cgi.gene_info_id = gn.gene_info_id
      AND gsi1.gene_id = g.gene_id
      AND g.gene_id = t.gene_id
      AND t.transcript_id = tsi.transcript_id
      AND tsi.stable_id = cti.transcript_stable_id
      AND cti.transcript_info_id = ti.transcript_info_id
      AND t.transcript_id = et.transcript_id
      AND et.exon_id = e.exon_id
      AND e.contig_id
      });
  $sth->execute;

  while (my @row = $sth->fetchrow_array()){
    $n++;

    # transform to chr coords
    my($gsi,$gn,$gt,$tsi,$tn,$erank,$eid,$ecid,$est,$eed,$esr,$es,$ep,$eep,$tiid,$tlid)=@row;

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
      my @row2=($gsi,$gn,$gt,$tsi,$tn,$erank,$eid,$ecst,$eced,$cname,$atype,$esr,$es,$ep,$eep,$tlid);
      push(@data,[@row2]);

      # record genes with no gene_description
      my $type="$atype:$cname";
      if(!$gdes{$gsi}){
	$missing_gdes{$type}->{$gt}->{$gsi}=$gn;
      }else{
	$missing_gdes{$type}->{$gt}->{$gsi}=1;
      }

      # record transcripts with no transcript_remark
      if(!$trii{$tiid}){
	$missing_tr{$gt}->{$tsi}="$gsi:$gn";
      }else{
	$missing_tr{$gt}->{$tsi}=1;
      }
      
      # record clones that each gsi are attached to and assembly for each gsi
      $gsi_clone{$gsi}->{"$cla.$clv"}=1;
      $type_gsi{$type}->{$gsi}=1;

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
	  print LOG "WARN: $gsi attached to contig $ecid (unknown)\n" if $opt_v;
	}
      }
    }
    last if ($opt_t && $n>=$opt_t);
  }

  # report all genes with missing descriptions
  if(!$stats && (!$report_only || $report_only{$ncheck})){
    print "[$ncheck] Genes with missing descriptions (see $opt_R) - add descriptions:\n";
    open (MOUT,">$opt_R") || die "cannot open missing descriptions file";
    foreach my $type (sort keys %missing_gdes){
      my($label,$atype,$cname)=type2label($type);
      print "sequence_set $label\n";
      print MOUT "sequence_set $label\n";
      foreach my $gt (sort keys %{$missing_gdes{$type}}){
	print " gene type $gt\n" if $gt eq 'Known';
	print MOUT " gene type $gt\n";
	my $n=0;
	my $nt=0;
	my $out='';
	foreach my $gsi (sort keys %{$missing_gdes{$type}->{$gt}}){
	  $nt++;
	  my $gname=$missing_gdes{$type}->{$gt}->{$gsi};
	  next if $gname eq '1';
	  $n++;
	  $out.="   $gsi $gname\n";
	}
	if($n==1){
	  print "   $n/$nt gene has a missing description\n$out" if $gt eq 'Known';
	  print MOUT "   $n/$nt gene has a missing description\n$out";
	}else{
	  print "   $n/$nt genes have missing descriptions\n$out" if $gt eq 'Known';
	  print MOUT "   $n/$nt genes have missing descriptions\n$out";
	}
      }
    }
    print "\n";
    close MOUT;

    # report all transcripts with missing_remarks
    #$ncheck++;
    print LOG "Transcripts with missing remarks (see $opt_r):\n";
    open (MOUT,">$opt_r") || die "cannot open remarks file";
    foreach my $gt (sort keys %missing_tr){
      my $n=0;
      my $nt=0;
      my $out='';
      foreach my $tsi (sort keys %{$missing_tr{$gt}}){
	my $gname=$missing_tr{$gt}->{$tsi};
	$nt++;
	next if $gname eq '1';
	$n++;
	$out.="  $tsi ($gname)\n";
      }
      if($n==1){
	print LOG " $n/$nt transcript of gene type $gt has a missing remark\n";
	print MOUT " $n/$nt transcript of gene type $gt has a missing remark:\n$out";
      }else{
	print LOG " $n/$nt transcripts of gene type $gt have missing remarks\n";
	print MOUT " $n/$nt transcripts of gene type $gt have missing remarks:\n$out";
      }
    }
    print "\n";
    close(MOUT);
  }

  my %n_offtrack;

  # report all offtrack genes
  my %orphan_gsi;
  foreach my $type (sort keys %type_gsi){

    my($label,$atype,$cname)=type2label($type);
    $n_offtrack{$label}->[0]=0;
    $n_offtrack{$label}->[1]=0;
    $n_offtrack{$label}->[2]=0;
    print LOG "sequence_set $label\n";

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
	print LOG " ERR1 $gsi ($gn) ss=\'$type\' has exon(s) off assembly:\n";
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
	print LOG "  on clones: $a2c $aoc $auc\n";
	print LOG "   ".join("\n   ",@{$excluded_gsi{$gsi}})."\n" if $opt_v;
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
	print LOG " [$n] $sv [$glist]\n";
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
	  print LOG " ERR2 $gsi ($gn) ss=\'$atype\' some exon(s) off agp:\n";
	}else{
	  print LOG " ERR2 $gsi ($gn) ss=\'$atype\' all exon(s) off agp:\n";
	}
	print LOG "   ".join("\n   ",@{$offagp_gsi{$gsi}})."\n" if $opt_v;
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
	print LOG " [$n] $sv [$glist]\n";
      }
    }

  }

  # big problem with orphans - how to tell which elements of assembly
  # are historical?  Partly dealt with by tracking versions...
  print LOG "offtrack genes on clones out of current sequence_sets\n";
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
    foreach my $type (sort keys %type){
      my($label)=type2label($type);
      $n_offtrack{$label}->[2]++;
    }
    print LOG " ERR3 $gsi ($gn) linked to =\'".join("\',\'",(keys %type))."\'; clones: ".
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
    print LOG "  found on clones: $a2c $aoc $auc\n";
    print LOG "   ".join("\n   ",@{$excluded_gsi{$gsi}})."\n" if $opt_v;
  }

  print LOG "wrote $n records to cache file $cache_file\n";
  print LOG "wrote $nexclude exons ignored as not in selected assembly\n";
  print LOG "skipped $nobs exons marked as obsolete\n";

  print LOG "\nNumber of offtrack gene problems by sequence_set and type (ERR1, ERR2, ERR3)\n";
  foreach my $label (sort keys %n_offtrack){
    printf LOG "%-20s %4d %4d %4d\n",$label,@{$n_offtrack{$label}};
  }

  print LOG "\nChecking consistency of translations\n";

  # attach translation information to exons, looking for exons that are part of both...
  # states 1: before; 2: coding; 3 endcoding; 4: after
  my %etls;
  my $last_tsi;
  my $last_eid;
  my $state;
  my($est,$estid,$eed,$eedid);
  my $nis=0;
  my $nodd=0;
  my $nss=0;
  foreach my $rdata (sort {
                           $a->[0] cmp $b->[0] ||
                           $a->[3] cmp $b->[3] ||
                           $a->[5]<=>$b->[5]
			 } @data){
    my($gsi,$gn,$gt,$tsi,$tn,$erank,$eid,$ecst,$eced,$cname,$atype,$esr,$es,$ep,$eep,$tlid)=@$rdata;

    # nothing to annotate if no translation
    next unless $tlid;

    # ignore sticky exons in this case
    next if($eid==$last_eid);
    $last_eid=$eid;

    # reset state
    if($tsi ne $last_tsi){
      $state=1;
      $last_tsi=$tsi;
    }

    if($tle{$tlid}){
      ($est,$estid,$eed,$eedid)=@{$tle{$tlid}};
      if($eid eq $estid){
	if($eid eq $eedid){
	  # single: ->3
	  if($state==1){
	    $state=3;
	  }else{
	    print LOG "FATAL $tlid, $eid: exon/translation order error $state => 6\n";
	  }
	}else{
	  # start: ->2
	  if($state==1){
	    $state=2;
	  }else{
	    print LOG "FATAL $tlid, $eid: exon/translation order error $state => 2\n";
	  }
	}
      }elsif($eid eq $eedid){
	if($state==2){
	  # end: ->3
	  $state=3;
	}else{
	  print LOG "FATAL $tlid, $eid: exon/translation order error $state => 4\n";
	}
      }else{
	if($state==3){
	  # middle: ->4
	  $state=4;
	}
      }
    }else{
      print LOG "FATAL no entry in translation table for translation_id $tlid\n";
    }
    if($etls{$eid}){
      my($state2,$tlid2)=@{$etls{$eid}};
      if($state2!=$state){
	if(($state==1 && $state2==4) || ($state==4 && $state==1)){
	  print LOG "  WARN: $eid used by two translations oddly: $tlid:$state; $tlid2:$state2\n";
	  $nodd++;
	}else{
	  print LOG "  ERROR: $eid used by two translations inconsistently: $tlid:$state; $tlid2:$state2\n";
	  $nis++;
	}
      }else{
	print LOG "  INFO: $eid used by two translation consistently: $tlid, $tlid2 $state\n" if $opt_V;
	$nss++;
      }
    }else{
      $etls{$eid}=[$state,$tlid];
    }
  }

  # loop again to check if any CDS exons (states 2,3) are used in transcripts with no translation
  my $nis2=0;
  for(my $i=0;$i<scalar(@data);$i++){
    my($gsi,$gn,$gt,$tsi,$tn,$erank,$eid,$ecst,$eced,$cname,$atype,$esr,$es,$ep,$eep,$tlid)=@{$data[$i]};
    my($state2,$tlid2);
    if($etls{$eid}){
      ($state,$tlid2)=@{$etls{$eid}};
    }else{
      $state=0;
    }
    push(@{$data[$i]},$state);
    next if($tlid);
    if($state==2 || $state==3){
      print LOG "ERROR: $eid used by translation and transcript inconsistently: $tlid2:$state; transcript $tsi\n";
      $nis2++;
    }
  }  

  print LOG "$nis exons used inconsistently by two translations - ERROR\n";
  print LOG "$nis2 exons used inconsistently by translation and transcript - ERROR\n";
  print LOG "$nodd exons used oddly by two translations - WARN\n";
  print LOG "$nss exons used consistently by two translations - INFO\n";

  print LOG "\nEND assembly processing\n\n";

  # if saving cache file
  if($make_cache){
    open(OUT,">$cache_file") || die "cannot open cache file $cache_file";
    foreach my $rdata (@data){
      print OUT join("\t",@$rdata)."\n";
    }
    close(OUT);
  }

}

# read list of bad translations so can report which genes have bad translations
my %bt;
my %bg;
if($opt_k){
  my $ne=0;
  open(IN,"$opt_k") || die "ERROR: cannot open $opt_k";
  my $old_tid;
  my $flag;
  while(<IN>){
    chomp;
    if(/remark:\s+(.*)/){
      if($flag){
	push(@{$bt{$old_tid}},$1);
      }
    }elsif(/^\s*$/){
    }else{
      my($gn,$tn,$tid,$ne,$type,$label,$nstop,@tstop)=split(/\s+/);
      my $tstop=join(' ',@tstop);
      $flag=1;
      if($gn=~/(\w+):(.*)/){
	my $prefix=$1;
	if($exclude_all || $exclude{$prefix}){
	  $ne++;
	  $flag=0;
	}
      }
      if($flag==1){
	$bt{$tid}=[$gn,$tn,$ne,$type,$label,$nstop,$tstop];
	push(@{$bg{$gn}},$tid);
	$old_tid=$tid;
      }
    }
  }
  print LOG "\n";
  print LOG scalar(keys %bt)." bad translations found in check translations output\n";
  print LOG "$ne genes with prefix excluded (reading from $opt_k)\n\n";
}

my %gsi;
my %gsi_sum;
my %tsi_sum;
my $n=0;
my $nobs=0;
my $nexclude=0;
my %ngtgnerr;
my %ngtgnerr2;
my %ngtgnerr3;

print LOG "START gene processing\n\n";

# unpack data array
foreach my $rdata (@data){
  my($gsi,$gn,$gt,$tsi,$tn,$erank,$eid,$ecst,$eced,$cname,$atype,$esr,$es,$ep,$eep,$tlid,$tls)=
      @$rdata;

  # skip obs genes
  if($gt eq 'obsolete'){
    $nobs++;
    next;
  }

  # gn, gt, tn can all have prefixes, and they should be consistent:
  # warn for mislabelled genes/transcripts
  my $gnpre='';
  if($gn=~/^(\w+):/){
    $gnpre=$1;
  }
  my $tnpre='';
  if($tn=~/^(\w+):/){
    $tnpre=$1;
  }
  my $gtpre='';
  if($gt=~/^(\w+):/){
    $gtpre=$1;
  }
  #print "DEBUG|$gnpre|$gtpre|$tnpre|$exclude_all|\n";
  
  if($gnpre ne $gtpre){
    if(!$ngtgnerr2{$gn}){
      $ngtgnerr2{$gn}=1;
      print LOG "WARN2 prefix mismatch: name=\'$gn\', type=\'$gt\'\n" if $opt_v;
    }
  }

  if($gnpre ne $tnpre){
    if(!$ngtgnerr3{$tn}){
      $ngtgnerr3{$tn}=1;
      print LOG "WARN3 prefix mismatch: name=\'$gn\', name=\'$tn\'\n" if $opt_v;
    }
  }

  my $eflag=0;
  if($exclude_all && ($gnpre || $gtpre || $tnpre)){
    $eflag=1;
  }elsif($exclude && ($gnpre || $gtpre || $tnpre)){
    foreach my $excl (split(/,/,$exclude)){
      if($gnpre eq $excl || $gtpre eq $excl || $tnpre eq $excl){
	$eflag=1;
	last;
      }
    }
  }
  if($eflag){
    $nexclude++;
    next;
  }

  # expect transcripts to stay on same assembly
  my $type="$atype:$cname";
  if($tsi_sum{$tsi}){
    my($tn2,$type2)=@{$tsi_sum{$tsi}};
    if($type2 ne $type){
      print LOG "ERROR: $gsi ($gn): $tsi ($tn) on type:chr $type and $type2\n";
    }
  }else{
    $tsi_sum{$tsi}=[$tn,$type];
  }

  push(@{$gsi{$type}->{$gsi}},[$tsi,$erank,$eid,$ecst,$eced,$esr,$es,$ep,$eep,$tlid,$tls]);

  # these relationships should be fixed
  $gsi_sum{$gsi}=[$gn,$gt];

  $n++;
}
close(IN);
print LOG scalar(keys %gsi_sum)." genes read; $nobs obsolete skipped; $nexclude excluded\n";
print LOG "$n name relationships read\n\n";
print LOG scalar(keys %ngtgnerr)." naming errors (GD:name; type)\n";
print LOG scalar(keys %ngtgnerr2)." naming errors (name; GD:type\n";

# another option for script, to use cache file to generate gene count stats
if($stats){
  my %stats;
  foreach my $type (keys %gsi){
    foreach my $gsi (keys %{$gsi{$type}}){
      my($gn,$gt)=@{$gsi_sum{$gsi}};
      foreach my $set ($type,'All'){
	foreach my $type2 ($gt,'All'){
	  # count genes
	  $stats{$set}->{$type2}->[0]++;
	  my %t;
	  my %e;
	  foreach my $re (@{$gsi{$type}->{$gsi}}){
	    my($tsi,$erank,$eid)=@$re;
	    $t{$tsi}++;
	    $e{$eid}++;
	    # number of exons
	    $stats{$set}->{$type2}->[2]++;
	  }
	  # number of transcripts
	  $stats{$set}->{$type2}->[1]+=scalar(keys %t);
	  # number of unique exons
	  $stats{$set}->{$type2}->[3]+=scalar(keys %e);
	}
      }
    }
  }
  foreach my $type (sort keys %stats){
    foreach my $type2 (sort keys %{$stats{$type}}){
      printf "%-20s %-25s %6d %6d %6d %6d\n",
      $type,$type2,@{$stats{$type}->{$type2}};
    }
  }
  exit 0;
}

# another option for script, to use cache file to generate gene count stats
if($ccds){

  my %ccds_list;
  if($ccds_list){
    if(-e $ccds_list){
      open(TMP,$ccds_list) || die "cannot open $ccds_list";
      my $n=0;
      my $no=0;
      while(<TMP>){
	chomp;
	my($hugo,$ccds,$chr,$ensid)=split(/\t/);
	if($ccds=~/^CCDS/){
	  $ccds_list{"CCDS:$ccds"}=[$hugo,$chr,$ensid];
	  $n++;
	}else{
	  $no++;
	}
      }
      close(TMP);
      print "Status of CCDS entries in list $ccds_list\n";
      print "$n priority ccds ids read; $no in list not CCDS entries\n";
    }else{
      print "Failed to open CCDS list $ccds_list\n";
      exit 0;
    }
  }

  # build a list of translations
  my %tle;
  {
    my $sth=$dbh->prepare("select * from translation");
    $sth->execute();
    while (my @row = $sth->fetchrow_array()){
      my($tlid,$est,$estid,$eed,$eedid)=@row;
      $tle{$tlid}=[$est,$estid,$eed,$eedid];
    }
  }

  # tsi->tn via tsi_sum [should be CCDSid]
  foreach my $type (keys %gsi){
    my($label,$atype,$cname)=type2label($type);
    print "\nChecking \'$atype\' (chr \'$cname\')\n";

    my %ccds;
    my %ct2g;
    my %t2g;
    my %tsi;
    my %e2t;
    my %eall;
    my $ccds_tag;
    foreach my $gsi (keys %{$gsi{$type}}){
      my($gn,$gt)=@{$gsi_sum{$gsi}};
      if($gn=~/CCDS:/){
	$ccds_tag=1;
      }else{
	$ccds_tag=0;
      }
      foreach my $re (@{$gsi{$type}->{$gsi}}){
	my($tsi,$erank,$eid,$ecst,$eced,$esr,$es,$ep,$eep,$tlid)=@$re;
	# merge sticky (duplicate from elsewhere)
	$erank--;
	# id, st, ed, esr, strand, phase, endphase
	if($tsi{$tsi}->[$erank]){
	  # assume merging a sticky...
	  my($eid2,$ecst2,$eced2,$esr2,$es2,$ep2,$eep2,$tlid2)=@{$tsi{$tsi}->[$erank]};
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
	      my $out;
	      my $diff;
	      if($eced2-$ecst>$eced-$ecst2){
		$out="$ecst-$eced..$ecst2-$eced2\n";
		$diff=$ecst2-$eced;
		$eced=$eced2;
	      }else{
		$out="$ecst2-$eced2..$ecst-$eced\n";
		$diff=$ecst-$eced2;
		$ecst=$ecst2;
	      }
	      if($diff>1){
		print LOG "ERROR: merging sticky exons $eid over gap in $tsi: $out";
	      }else{
		print LOG "ERROR: merging overlapping sticky exons $eid in $tsi: $out";
	      }
	    }
	    $tsi{$tsi}->[$erank]=[$eid,$ecst,$eced,$esr3,$es,$ep,$eep,$tlid2];
	  }else{
	    print LOG "FATAL: Duplicate rank for $tsi, $erank\n";
	  }
	}else{
	  $tsi{$tsi}->[$erank]=[$eid,$ecst,$eced,$esr,$es,$ep,$eep,$tlid];
	}
	  
	if($ccds_tag){
	  # list of CCDS gene, transcript
	  $ccds{$gsi}->{$tsi}=1;
	  $ct2g{$tsi}=$gsi;
	}else{
	  $t2g{$tsi}=$gsi;
	}
      }
    }
    print " Found ".scalar(keys %tsi)." transcripts; ".
	scalar(keys %ccds)." CCDS genes;\n";

    # build translation set of exons
    my %tsitl;
    my($est,$estid,$eed,$eedid)=0;
  LOOP:
    foreach my $tsi (keys %tsi){
      my $erankt=-1;
      my $flag;
      for(my $erank=0;$erank<scalar(@{$tsi{$tsi}});$erank++){
	if(!$tsi{$tsi}->[$erank]){
	  print "ERR: erank $erank does not exist for $tsi - off track genes?\n";
	  next;
	}
	my($eid,$ecst,$eced,$esr,$es,$ep,$eep,$tlid)=@{$tsi{$tsi}->[$erank]};
	next LOOP if $tlid==0;
	if($erank==0){
	  if($tle{$tlid}){
	    ($est,$estid,$eed,$eedid)=@{$tle{$tlid}};
	  }else{
	    print "ERR: translation $tlid missing from DB\n";
	    exit 0;
	  }
	}
	if($flag==0 && $eid==$estid){
	  # first exon
	  my $necst=$ecst;
	  my $neced=$eced;
	  $flag=1;
	  if($es==1){
	    $necst=($ecst+$est-1);
	    if($eid==$eedid){
	      $flag=2;
	      $neced=($ecst+$eed-1);
	    }
	  }else{
	    $neced=($eced-$est+1);
	    if($eid==$eedid){
	      $flag=2;
	      $necst=($eced-$eed+1);
	    }
	  }
	  $erankt++;
	  $tsitl{$tsi}->[$erankt]=[$eid,$necst,$neced,$esr,$es,$ep,$eep,$erank];
	}elsif($flag==1){
	  my $necst=$ecst;
	  my $neced=$eced;
	  if($eid==$eedid){
	    if($es==1){
	      $neced=($ecst+$eed-1);
	    }else{
	      $necst=($eced-$eed+1);
	    }
	    $flag=2;
	    # temp hack - if CCDS were loaded without stop...trim here to match - wrong
	    # think to do as stop could start a new exon...
	    if($ccds_stop){
	      $neced-=3;
	      if($neced<$ecst){
		print "error: $tsi ccds stop fix failed due to small exon\n";
		$neced+=3;
	      }
	    }
	  }
	  $erankt++;
	  $tsitl{$tsi}->[$erankt]=[$eid,$necst,$neced,$esr,$es,$ep,$eep,$erank];
	}elsif($flag==2){
	  $flag=3;
	}
	my $erankt_flag=-1;
	if($flag==1 || $flag==2){
	  $erankt_flag=$erankt;
	}
	my $ccds_flag=0;
	if($ct2g{$tsi}){
	  $ccds_flag=1;
	}
	push(@{$eall{$ecst}->{$eced}},[$tsi,$erank,$erankt_flag,$ccds_flag]);
      }
      if($flag<2){
	# never found whole translation...
	print "ERR: complete translation not found $tsi: $flag\n";
      }
    }
    print " Found ".scalar(keys %tsitl)." translations;\n";
    
    # compare all CCDS to non CCDS
    # loop over CCDS:
    my $nccdsg=0;
    my $nccdst=0;
    my $nccdstp=0;
    my $nccdsto=0;
    my %nccdstp;
    my %nccdsto;
    my %nccdst;
    my @matcht=(
		'no overlap',
		'overlap different strand',
		'transcript exon overlap',
		'transcript exon exact match',
		'translation exon overlap',
		'translation exon exact match, different phase',
		'translation exon exact match',
		);
    my @matchc;
    my @ccds;
    {
      my %t2g;
      foreach my $gsi (keys %ccds){
	foreach my $tsi (keys %{$ccds{$gsi}}){
	  my($tn,$tt)=@{$tsi_sum{$tsi}};
	  $t2g{$tn}=$gsi;
	}
      }
      my %ugsi;
      foreach my $tn (sort keys %t2g){
	my $gsi=$t2g{$tn};
	if(!$ugsi{$gsi}){
	  $ugsi{$gsi}=1;
	  push(@ccds,$gsi);
	}
      }
    }
    foreach my $gsi (@ccds){
      my($gn,$gt)=@{$gsi_sum{$gsi}};
      last if($opt_n && $nccdsg>$opt_n);
      my $gsi_out="$gn ($gsi)\n";
      foreach my $tsi (sort {$tsi_sum{$ccds{$gsi}->{$a}}->[0]<=>
				 $tsi_sum{$ccds{$gsi}->{$a}}->[1]} keys %{$ccds{$gsi}}){
	my($tn,$tt)=@{$tsi_sum{$tsi}};
	next if($ccds_id && $ccds_id ne $tn);
	next if($ccds_list && !$ccds_list{$tn});
	if($gsi_out){
	  $nccdsg++;
	  print " [$nccdsg] ".$gsi_out;
	  $gsi_out='';
	}
	print "  $tn ($tsi)\n";
	$nccdst++;
	my $nexon=scalar(@{$tsi{$tsi}});
	# perfect march score
	my $mmatch=$nexon*6;
	# quality of matched exons by id
	my %tsim;
	my @ematch;
	my %rmatch;
	# loop over exons of this ccds transcript
	for(my $erank=0;$erank<scalar(@{$tsi{$tsi}});$erank++){
	  my $erank1=$erank+1;
	  my($eid,$ecst,$eced,$esr,$es,$ep,$eep,$tlid);
	  if($tsi{$tsi}->[$erank]){
	    ($eid,$ecst,$eced,$esr,$es,$ep,$eep,$tlid)=@{$tsi{$tsi}->[$erank]};
	  }else{
	    print "ERR: no exon data for $gsi:$tsi:$erank\n";
	    next;
	  }
	  # compare to others
	  foreach my $ecst2 (sort {$a<=>$b} keys %eall){
	    last if $ecst2>$eced;
	    foreach my $eced2 (sort {$a<=>$b} keys %{$eall{$ecst2}}){
	      next if $eced2<$ecst;
	      # if match, record
	      foreach my $rexon (@{$eall{$ecst2}->{$eced2}}){
		my($tsi2,$erank2,$erankt2,$ccds_flag)=@$rexon;
		# hack test
		next if $tsi2 eq 'OTTHUMT00000102796';

		# don't compare against self
		next if $ccds_flag;

		# compare overlap
		my $match=0;
		if(intersect($ecst,$eced,$ecst2,$eced2)){
		  my($eid3,$ecst3,$eced3,$esr3,$es3,$ep3,$eep3,$erank4)=
		      @{$tsi{$tsi2}->[$erank2]};
		  if($es!=$es3){
		    $match=1;
		  }elsif($ecst==$ecst2 && $eced==$eced2){
		    $match=3;
		  }else{
		    $match=2;
		  }
		}
		# refine against translation if exists
		# record
		if($erankt2>=0 && $match>1){
		  my($eid3,$ecst3,$eced3,$esr3,$es3,$ep3,$eep3,$erank4)=
		      @{$tsitl{$tsi2}->[$erankt2]};
		  $rmatch{$tsi2}->{$erankt2}=$erank1;
		  #print "rmatch: $tsi2: $erankt2, $erank1\n";
		  if(intersect($ecst,$eced,$ecst3,$eced3)){
		    if($ecst==$ecst3 && $eced==$eced3){
		      if($ep!=$ep3){
			$match=5;
		      }else{
			$match=6;
		      }
		    }else{
		      $match=4;
		    }
		  }
		}
		if($match){
		  push(@{$ematch[$erank]->{$tsi2}},[$erank2,$erankt2,$match]);
		}
	      }
	    }
	  }
	}
	# count up scores afterwards, else where multiple matches can end up 
	# with a perfect match by mistake
	for(my $erank=0;$erank<scalar(@{$tsi{$tsi}});$erank++){
	  foreach my $tsi2 (keys %{$ematch[$erank]}){
	    my $matchmx=0;
	    foreach my $rematch (@{$ematch[$erank]->{$tsi2}}){
	      my($erank2,$erankt2,$match)=@$rematch;
	      if($match>$matchmx){$matchmx=$match;}
	    }
	    $tsim{$tsi2}+=$matchmx;
	    #print "$erank: $tsi2: $match, $tsim{$tsi2}\n";
	  }
	}
		  

	# check all matched translation to count exons not matched...
	my %unused;
	# number of unused exons by id (-ve for sorting)
	my %tsim2;
	foreach my $tsi2 (keys %tsim){
	  my $unused='';
	  my $nskip=0;
	  my $nexon=scalar(@{$tsitl{$tsi2}});
	  my @unused;
	  my $first=0;
	  my $flag_skipped=[];
	  for(my $erank=0;$erank<$nexon;$erank++){
	    my $erank1=$erank+1;
	    if($rmatch{$tsi2}->{$erank}){
	      my $erankx=($rmatch{$tsi2}->{$erank})-1;
	      $first=1;
	      if(scalar(@{$flag_skipped})){
		push(@{$unused[1]},@{$flag_skipped});
		#print "$tsi2: $erank: 1:\n";
		$flag_skipped=[];
	      }
	    }else{
	      #print "no match: $tsi2, $nexon\n";
	      $nskip--;
	      if($first==0){
		# missing initial exons
		push(@{$unused[0]},$erank1);
	      }else{
		push(@{$flag_skipped},$erank1);
		#print "$tsi2: $erank: 0:\n";
	      }
	    }
	  }
	  if(scalar(@{$flag_skipped})){
	    push(@{$unused[2]},@{$flag_skipped});
	    #print "$tsi2: post: 2:\n";
	  }
	  if($unused[0] && scalar(@{$unused[0]})){
	    $unused='Initial: '.join(',',@{$unused[0]});
	  }
	  if($unused[1] && scalar(@{$unused[1]})){
	    if($unused){$unused.='; '}
	    $unused.='Internal: '.join(',',@{$unused[1]});
	  }
	  if($unused[2] && scalar(@{$unused[2]})){
	    if($unused){$unused.='; '}
	    $unused='Terminal: '.join(',',@{$unused[2]});
	  }
	  $tsim2{$tsi2}=$nskip;
	  $unused{$tsi2}=$unused;
	  #print "count: $tsi2, $nexon, $nskip, $unused\n";
	}

	# report transcript(s) that have best match to CCDS

	my $found=0;
	my %pre;
	foreach my $tsi2 (reverse sort {$tsim{$a}<=>$tsim{$b}
					|| $tsim2{$a}<=>$tsim2{$b}
					|| &order_by_prefix} keys %tsim){
	  my($tn2,$tt2)=@{$tsi_sum{$tsi2}};
	  my($pre)=($tn2=~/^(\w+):/);
	  if($pre eq ''){
	    $found=1;
	  }elsif($pre{$pre}){
	    $nccdst{$pre}=1;
	    next;
	  }
	  $pre{$pre}=1;

	  my $gsi2=$t2g{$tsi2};
	  my($gn2,$gt2)=@{$gsi_sum{$gsi2}};
	  my $nmatch=$tsim{$tsi2};
	  my @out;
	  my $mismatch_out='';
	  my $multiple_out='';
	  my $multiple_out1='';
	  my $im=0;
	  for(my $erank=0;$erank<$nexon;$erank++){
	    my $erank1=$erank+1;
	    my @rematch;
	    if($ematch[$erank]->{$tsi2}){
	      @rematch=@{$ematch[$erank]->{$tsi2}};
	    }else{
	      $rematch[0]=[-1,-1,0];
	    }
	    my @list;
	    my @list1;
	    foreach my $rematch (sort {$a->[1]<=>$b->[1]} @rematch){
	      my($erank2,$erankt2,$match)=@$rematch;
	      $matchc[$match]++;
	      $out[0].=sprintf("%3d",$erank1);
	      if($erankt2>=0){
		push(@list,$erankt2+1);
		$out[1].=sprintf("%3d",$erankt2+1);
	      }else{
		$out[1].='  -';
	      }
	      if($erank2>=0){
		push(@list1,$erank2+1);
		$out[2].=sprintf("%3d",$erank2+1);
	      }else{
		$out[2].='  -';
	      }    
	      $out[3].=sprintf("%3d",$match);
	      if($match<6 && $match>0 && $erankt2>=0){
		my($eid2,$ecst2,$eced2,$esr2,$es2,$ep2,$eep2,$erank2)=@{$tsi{$tsi}->[$erank]};
		my($eid,$ecst,$eced,$esr,$es,$ep,$eep)=@{$tsitl{$tsi2}->[$erankt2]};		
		$mismatch_out.="     [ccds exon $erank1] match $match: [CCDS]:$ecst2-$eced2 [Annotation]:$ecst-$eced\n";
	      }
	    }
	    if(@list>1){
	      if($multiple_out){$multiple_out.='; ';}
	      $multiple_out.="$erank1->".join(',',@list);
	    }
	    if(@list1>1){
	      if($multiple_out1){$multiple_out1.='; ';}
	      $multiple_out1.="$erank1->".join(',',@list1);
	    }
	  }
	  my $flag_perfect=0;
	  if($nmatch==$mmatch && $unused{$tsi2} eq ''){
	    $flag_perfect=1;
	    # all CCDS exons match, but are there extra exons in tsi2?
	    print "   PERFECT ";
	    if($pre){
	      $nccdstp{$pre}++;
	    }else{
	      $nccdstp++;
	    }
	  }else{
	    print "   partial ";
	    if($pre){
	      $nccdsto{$pre}++;
	    }else{
	      $nccdsto++;
	    }
	  }
	  print "match ($nmatch/$mmatch): ";
	  print "$tn2 ($tsi2) $gn2 ($gsi2) $gt2\n";
	  print $mismatch_out."\n";
	  # don't output if perfect match:
	  if(!$flag_perfect){
	    print "    CCDS exons:        ".$out[0]."\n";
	    print "    Translation exons: ".$out[1]."\n";
	    print "    Transcript exons:  ".$out[2]."\n";
	    print "    Match score:       ".$out[3]."\n";
            print "     Unused translation exons: ".$unused{$tsi2}."\n" if $unused{$tsi2};
            print "     Multiple translation exons: ".$multiple_out."\n" if $multiple_out;
            print "     Multiple transcript exons: ".$multiple_out1."\n" if $multiple_out1;
	  }
	  print "\n";
	  last if $found;
	}
      }
    }
    print "\n";
    print " $nccdsg CCDS genes; $nccdst CCDS transcripts\n";
    print " $nccdstp transcripts match perfectly; $nccdsto transcripts overlap\n";
    print " Following transcripts with prefixes fit better than any trancript without prefix\n" 
	if scalar (keys %nccdst);
    foreach my $pre (sort keys %nccdst){
      my $np=0;
      if($nccdstp{$pre}){$np=$nccdstp{$pre};}
      my $no=0;
      if($nccdsto{$pre}){$no=$nccdsto{$pre};}
      print " $pre: $np transcripts match perfectly; $no transcripts overlap\n";
    }

    print " matches by exon:\n";
    for(my $i=0;$i<7;$i++){
      printf "  %4d match score $i (%s)\n",$matchc[$i],$matcht[$i];
    }

  }
  exit 0;
}

# get clones from assemblies of interest
my %a;
if(!$flag_no_db){
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
  print LOG "$n contigs read from assembly\n";
}

my $nsticky=0;
my $nexon=0;
my %dup_exon;
my $nmc=0;
my $nmcb=0;
my $nl=0;
my $flag_v;
my $nip=0;
my $npntr=0;
my $npstr=0;
my $nos=0;
my %t2e;
my %e2t;
my %e;
my %elink;
my %eall;
my %e2g;

# process bad translations
$ncheck++;
my $flag_stop;
if(!$report_only || $report_only{$ncheck}){
  if($opt_k){
    print "[$ncheck] Following genes have STOP codons - editing or seleno labelling required\n";
    $flag_stop=1;
  }else{
    print "[$ncheck] genes with STOP codons - NOT CHECKED (-k file not given)\n\n";
  }
}
if($flag_stop){
  foreach my $type (sort keys %gsi){
    my($label,$atype,$cname)=type2label($type);
    print "\nChecking \'$atype\' (chr \'$cname\')\n";
    foreach my $gsi (keys %{$gsi{$type}}){
      my($gn,$gt)=@{$gsi_sum{$gsi}};
      if($bg{$gn}){
	# because -k output is keyd off genename, which may not be unique (alleles)
	# have to do this convoluted lookup off TIDs - pretty stupid!
	my $out="  Translations in $gsi ($gn) have stops\n";
	my %tid;
	%tid=map{$_->[0],1}@{$gsi{$type}->{$gsi}};
	my $flag_ok;
	foreach my $tid (@{$bg{$gn}}){
	  next unless $tid{$tid};
	  my($gn,$tn,$ne,$type,$label,$nstop,$tstop,@remarks)=@{$bt{$tid}};
	  if(!$report_ok_seleno){
	    next if $label eq 'S-OK';
	  }
	  $flag_ok=1;
	  $out.="    $tid $tn $ne $type $label $nstop $tstop\n";
	  foreach my $remark (@remarks){
	    $out.="      Remark: $remark\n";
	  }
	}
	print $out if $flag_ok;
      }
    }
  }
  print "\n\n";
}

# under development:
# - needs to be across sequence_sets, but with some idea of haplotypes
# - needs to be aware of ends added by james' locus name separation script, but not trip
# over legitimate names.
$ncheck++;
if(!$report_only || $report_only{$ncheck}){
  my $ngi=0;
  my $out;
  foreach my $type (sort keys %gsi){
    my($label,$atype,$cname)=type2label($type);
    $out.="\nChecking \'$atype\' (chr \'$cname\')\n";
    my %gn;
    foreach my $gsi (keys %{$gsi{$type}}){
      my($gn,$gt)=@{$gsi_sum{$gsi}};
      my $gnt=$gn;
      #if($gn=~/^(.*)(\-\d)$/){
	#$out.="    $gsi ($gt) $gn has appended version ($2) - duplicate?\n";
	#$gnt=$1;
      #}
      if($gn{$gnt}){
	my $gsi2=$gn{$gnt};
	my($gn2,$gt2)=@{$gsi_sum{$gsi2}};
	$ngi++;
	$out.="  $gsi ($gt) and $gsi2 ($gt2) both have same name $gn:$gn2\n";
      }else{
	$gn{$gnt}=$gsi;
      }
    }
  }
  print "[$ncheck] $ngi Genes have identical names - genes may need renaming\n$out\n";
}

$ncheck++;
my $no_trans_overlap;
if(!$report_only || $report_only{$ncheck}){
  print "[$ncheck] Genes composed of transcripts that do not overlap - transcripts may need merging\n";
}else{
  $no_trans_overlap=1;
}
open(OUT,">$opt_o") || die "cannot open $opt_o";
open(OUT2,">$opt_p") || die "cannot open $opt_p";
open(OUT3,">$opt_q") || die "cannot open $opt_q";
foreach my $type (sort keys %gsi){
  my($label,$atype,$cname)=type2label($type);
  print "\nChecking \'$atype\' (chr \'$cname\')\n" unless $no_trans_overlap;
  foreach my $gsi (keys %{$gsi{$type}}){

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
    my %ephases;
    my %etrans;
    # look for overlapping exons and group exons into transcripts
    # (one gene at a time)
    foreach my $rt (sort {
                          $a->[0]<=>$b->[0] || 
                          $a->[1]<=>$b->[1] || 
                          $a->[5]<=>$b->[5]
			    } @{$gsi{$type}->{$gsi}}){
      my($tsi,$erank,$eid,$ecst,$eced,$esr,$es,$ep,$eep,$tlid,$tls)=@{$rt};
      if($e{$gsi}->{$eid}){
	# either stored as sticky rank2 or this is sticky rank2
	if($eids{$eid} || $esr>1){

	  my($st,$ed,$es,$ep,$eep,$tlid,$tls)=@{$e{$gsi}->{$eid}};

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
	    $e{$gsi}->{$eid}=[$st,$ed,$es,$ep,$eep,$tlid,$tls];
	    $nsticky++;
	  }elsif($eced+1==$st){
	    $st=$ecst;
	    $e{$gsi}->{$eid}=[$st,$ed,$es,$ep,$eep,$tlid,$tls];
	    $nsticky++;
	  }else{
	    print LOG "ERROR: duplicate exon id $eid, but no sticky alignment\n";
	  }
	}
      }else{
	my $flag;
	
	# check consistency of phase of exon
	# and consistency wrt to translation of each instance of each exon
	# (note: before $eid->$eid2 in case of duplication)
	my($t,$p);
	if($tlid==0){
	  $t=1;
	  $p=0;
	}else{
	  $t=0;
	  $p=1;
	}
	if(!$etrans{$eid}){
	  my $flag_noncoding=0;
	  if($ep==-1 || $eep==-1){
	    $flag_noncoding=1 if $ep==-1;
	    if($ep+$eep!=-2){
	      print OUT3 "ERR1 $eid $ep $eep inconsistent noncoding phases\n";
	      $nip++;
	    }
	  }
	  $etrans{$eid}=[$flag_noncoding,$t,$p,$ep,$eep];
	}else{
	  my($f,$t1,$p1,$ep,$eep)=@{$etrans{$eid}};
	  $t1+=$t;
	  $p1+=$p;
	  $etrans{$eid}=[$f,$t1,$p1,$ep,$eep];
	}

	# compare current exon to all existing ones...
	foreach my $eid2 (keys %{$e{$gsi}}){
	  my($st,$ed,$es2,$ep2,$eep2,$tlid2,$tls)=@{$e{$gsi}->{$eid2}};
	  if($st==$ecst && $ed==$eced){
	    # duplicate exons
	    if($es!=$es2){
	      print OUT3 "NON-DUP: $eid, $eid2 identical but on opposite strands!\n";
	      $nos++;
	    }elsif($ep!=$ep2){
	      print OUT3 "NON-DUP: $eid, $eid2 identical but on diff phases ($ep,$ep2)\n";
	    }elsif($eep!=$eep2){
	      print OUT3 "WARN NON-DUP: $eid, $eid2 identical but diff end phases ($eep,$eep2) [$ep,$ep2]\n";
	    }elsif($dup_exon{$eid}==$eid2 || $dup_exon{$eid2}==$eid){
	      # don't report again
	      print LOG "should never happen $eid, $eid2\n";
	    }
	    # if seen this phase before, for a different eid, then a duplicate - delete
	    my $dflag=0;
	    foreach my $rp (@{$ephases{$eid2}}){
	      my($eid3,$es3,$ep3,$eep3)=@$rp;
	      if($eid!=$eid3 && $es==$es3 && $ep==$ep3 && $eep==$eep3){
		$dflag=$eid3;
	      }
	    }
	    if($dflag){
	      if($dup_exon{$eid}!=$eid2){
		$dup_exon{$eid}=$eid2;
		print OUT2 "$eid\t$dflag\t$st\t$ed\n";
	      }
	    }else{
	      push(@{$ephases{$eid2}},[$eid,$es,$ep,$eep]);
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
	  $e{$gsi}->{$eid}=[$ecst,$eced,$es,$ep,$eep,$tlid,$tls];
	  push(@{$ephases{$eid}},[$eid,$es,$ep,$eep]);
	  push(@{$eall{$ecst}->{$eced}},$eid);
	  $eids{$eid}=$esr if $esr>1;
	  $nexon++;
	}
      }
      push(@{$t2e{$gsi}->{$tsi}},$eid);
      push(@{$e2t{$gsi}->{$eid}},$tsi);
      if($e2g{$eid} && $e2g{$eid} ne $gsi){
	# eids should only be part of a single gid
	print LOG "FATAL $eid part of $gsi and $e2g{$eid}\n";
      }else{
	$e2g{$eid}=$gsi;
      }
    }

    # report consistency of exon phase wrt translation
    foreach my $eid (keys %etrans){
      my($f,$t,$p,$ep,$eep)=@{$etrans{$eid}};
      if($f==0 && $t){
	if($p){
	  print OUT3 "ERR3 $eid $ep $eep exon has phase when sometimes translation\n";
	  $npstr++;
	}else{
	  print OUT3 "ERR2 $eid $ep $eep exon has phase when never translation\n";
	  $npntr++;
	}
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

    if(!$no_trans_overlap){
      my $cl=new cluster();
      # link exons by transcripts
      foreach my $tsi (keys %{$t2e{$gsi}}){
	$cl->link([@{$t2e{$gsi}->{$tsi}}]);
	print LOG "D: $tsi ".join(',',@{$t2e{$gsi}->{$tsi}})."\n" if $flag_v;
      }
      # link exons by overlap
      foreach my $eid (keys %{$elink{$gsi}}){
	$cl->link([$eid,@{$elink{$gsi}->{$eid}}]);
	print LOG "D: $eid ".join(',',@{$elink{$gsi}->{$eid}})."\n" if $flag_v;
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
	  print " Cluster $ncid: ".join(',',(sort keys %tcl))."\n";
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
	    # if read_cache may not have DB, in which case skip this step
	    if(!$flag_no_db){
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
	    }
	    if($nc>0 && $nc<=2){
	      print $out;
	      $nmcb++;
	    }
	  }
	  print "  $tsi ($tn): $st-$ed\n";
	  $last_ed=$ed if $ed>$last_ed;
	}
	$nmc++;
	print "\n";
      }
    }

  }
}
print LOG scalar(keys %dup_exon)." duplicate exons\n";
print LOG "$nmc genes with non overlapping transcripts; $nmcb cases gap crosses single clone boudary\n";
print LOG "found $nexon exons; $nsticky sticky exons\n";
print LOG "$nip exons have inconsistent noncoding phases;\n";
print LOG "$npstr exons have phase when sometimes translation; $npntr exons have phase when never translation\n";

close(OUT);
close(OUT2);
close(OUT3);

$ncheck++;
if(!$report_only || $report_only{$ncheck}){
  print "\n[$ncheck] $nl large transcripts found (see $opt_o) - annotation errors?\n\n";
}

$ncheck++;
if(!$report_only || $report_only{$ncheck}){
  # global check on duplicate exons
  # look for cases where exact duplicate exons are part of different genes
  # (note: considers duplicate even when phases are different)
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
  print "[$ncheck] $ngcl Clusters of genes which share identical exons - may be duplicates:\n";
  if($ngcl>0){
    my %out;
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
      my @tsi=$tcl->cluster_members($ctsi[0]);
      my($tn,$type)=@{$tsi_sum{$tsi[0]}};
      $out{$type}.=" Cluster $igcl: ".scalar(@gsi)." genes; ".scalar(@ctsi).
	  " sets of duplicated transcripts\n";

      my $itcl=0;
      foreach my $tcid (@ctsi){
	$itcl++;
	my @tsi=$tcl->cluster_members($tcid);
	$out{$type}.="  Transcript set $itcl: ".scalar(@tsi)." transcripts\n";
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
	  my($gn,$gt)=@{$gsi_sum{$gsi}};
	  $out{$type}.="  $gsi ($gn, $gt) $ntd/$nt transcripts in duplication:\n";
	  foreach my $tsi (sort keys %{$tset{$gsi}}){
	    my($tn)=@{$tsi_sum{$tsi}};
	    my($ned,$ne,@eo)=@{$tset{$gsi}->{$tsi}};
	    for($i=0;$i<scalar(@eo);$i++){
	      if($eo[$i]>0){
		$eo[$i]=$id{$eo[$i]};
	      }
	    }
	    $out{$type}.="    $tsi ($tn) $ned/$ne exons: ".join(' ',@eo)."\n";
	  }
	}
      }
      $out{$type}.="\n";
    }
    foreach my $type (sort keys %out){
      my($label,$atype,$cname)=type2label($type);
      print "sequence_set $label\n";
      print $out{$type};
    }
  }
  print "\n";
}

# new check - for each transcript, check all exons are sequential, same strand
# sensible direction etc.  Check orientation of all transcripts in a gene consistent
$ncheck++;
if(!$report_only || $report_only{$ncheck}){
  print "[$ncheck] Transcripts with out of order exons - fix required\n";
  my $neo=0;
  my $ned=0;
  my $ntd=0;
  foreach my $type (sort keys %gsi){
    my($label,$atype,$cname)=type2label($type);
    print "sequence_set $label\n";
    foreach my $gsi (keys %{$gsi{$type}}){
      my($gn,$gt)=@{$gsi_sum{$gsi}};
      # structure data
      my %tsi;
      foreach my $re (@{$gsi{$type}->{$gsi}}){
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
	      my $out;
	      my $diff;
	      if($eced2-$ecst>$eced-$ecst2){
		$out="$ecst-$eced..$ecst2-$eced2\n";
		$diff=$ecst2-$eced;
		$eced=$eced2;
	      }else{
		$out="$ecst2-$eced2..$ecst-$eced\n";
		$diff=$ecst-$eced2;
		$ecst=$ecst2;
	      }
	      if($diff>1){
		print LOG "ERROR: merging sticky exons $eid over gap in $tsi: $out";
	      }else{
		print LOG "ERROR: merging overlapping sticky exons $eid in $tsi: $out";
	      }
	    }
	    $tsi{$tsi}->[$erank]=[$eid,$ecst,$eced,$esr3,$es,$ep,$eep];
	  }else{
	    print LOG "FATAL: Duplicate rank for $tsi, $erank\n";
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
	  my $erank=$i+1;
	  if(!$tsi{$tsi}->[$i]){
	    print LOG "WARN $tsi: exon rank $erank is missing from this slice\n";
	    next;
	  }
	  my($eid,$ecst,$eced,$esr,$es,$ep,$eep)=@{$tsi{$tsi}->[$i]};
	  print LOG "WARN $tsi: unresolved sticky in $eid $esr\n" if $esr>1;
	  
	  # check consistent direction
	  if($dirt){
	    if($es!=$dirt){
	      print "  $tsi direction is $dirt, but exon $eid is $es\n";
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
		print "  ERROR: $gsi $tsi exon $erank ($eid) out of order $ecst-$eced follows $last ($dirt)\n";
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
		print "  ERROR: $gsi $tsi exon $erank ($eid) out of order $ecst-$eced follows $last ($dirt)\n";
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
	    print "  ERROR: $gsi has direction $dirg, but $tsi has direction $dirt\n";
	    $ntd++;
	  }
	}else{
	  $dirg=$dirt;
	}
	
      }
    }
  }
  print LOG "$neo exons are out of order; $ned exons have inconsistent direction\n";
  print LOG "$ntd transcripts have inconsistent direction\n";
}

print LOG "\nEND gene processing\n";

if(!$flag_no_db){
  $dbh->disconnect();
}

exit 0;

# in vega case, chromosome is most useful label (assembly.type may be 'VEGA')
# in otter case, assembly.type is most useful label
sub type2label{
  my $type = shift;
  my($atype,$cname)=split(/:/,$type);
  my $label;
  if($vega){
    $label=$type;
  }else{
    $label=$atype;
  }
  return $label,$atype,$cname;
}

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

sub intersect{
    my($i,$j,$i2,$j2)=@_;
    # 1    ---------           1 --------              1  -------------
    # 2 --------               2    --------           2     ------
    if(($i>=$i2 && $i<=$j2) || ($j>=$i2 && $j<=$j2) || ($i<$i2 && $j>$j2)){
	return 1;
    }else{
	return 0;
    }
}


sub order_by_prefix {
  my($n1)=($tsi_sum{$a}->[0]=~/^(\w+):/);
  my($n2)=($tsi_sum{$b}->[0]=~/^(\w+):/);
  if($n1 eq $n2){
    return 0;
  }elsif($n1 eq ''){
    return 1;
  }elsif($n2 eq ''){
    return -1;
  }else{
    return $n1 cmp $n2;
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
