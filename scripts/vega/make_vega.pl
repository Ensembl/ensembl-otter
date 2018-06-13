#!/usr/bin/env perl
# Copyright [2018] EMBL-European Bioinformatics Institute
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#      http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


# script to take meta information in an otter database and use it to
# transform a copy of the database (pipeline, gene merge) into an 'vega'
# database.

# maps type->chromosome; VEGA->type; checks that no contig is reused;
# replaces author information with vega_author information; removes
# unnecessary chromosome+assembly information;

# vega_sets labelled 'I' are shown only internally.  vega_sets
# labelled 'E' are show both internally and externally.

use strict;
use Getopt::Long;
use DBI;
use Sys::Hostname;
use Bio::Otter::Lace::SatelliteDB;
use Bio::EnsEMBL::DBSQL::DBAdaptor;

# hard wired
my $driver="mysql";

# default values
# reference otter db
my $port=3306;
my $pass;
my $host='humsrv1';
my $user='ensro';
my $db='otter_mouse';

# database to become vega db
my $port2=3352;
my $pass2;
my $host2='ecs4';
my $user2='ensadmin';
my $db2='mouse_vega040719_raw';

my $help;
my $phelp;
my $opt_v;
my $opt_t;
my $sel_vega_set;
my $sel_sequence_set;
my $opt_I;
my $ext;
my $pipe;
my $list;
my $transform;
my $filter_annotation;
my $vega_internal;
my $root_dir="/acari/work2/th";

my $f_root='vega_pipe_dump';
my $f_dump_def=$f_root.".csh";
my $f_dump=$f_dump_def;

my $opt_o='vega_transfer.csh';
my $opt_p='vega_transform.sql';

my $exclude_gene_stable_id='';
my $add;

$Getopt::Long::ignorecase=0;

GetOptions(
	   'port:s',    \$port,
	   'pass:s',    \$pass,
	   'host:s',    \$host,
	   'user:s',    \$user,
	   'db:s',      \$db,

	   'port2:s',   \$port2,
	   'pass2:s',   \$pass2,
	   'host2:s',   \$host2,
	   'user2:s',   \$user2,
	   'db2:s',     \$db2,

	   't',         \$opt_t,
	   'vega_set:s',     \$sel_vega_set,
	   'sequence_set:s', \$sel_sequence_set,
	   'external',  \$ext,
	   'pipe',      \$pipe,
	   'list',      \$list,
	   'filter_annotation',    \$filter_annotation,
	   'vega_internal',        \$vega_internal,
	   'transform', \$transform,
	   'exclude_gene_stable_id:s', \$exclude_gene_stable_id,
	   'add', \$add,

	   'o:s',       \$opt_o,
	   'p:s',       \$opt_p,
	   'root_dir:s',\$root_dir,
	   'pipe_root:s',   \$f_root,
	   'pipe_script:s', \$f_dump,

	   'help',      \$phelp,
	   'h',         \$help,
	   'v',         \$opt_v,
	   'I',         \$opt_I,
	   );

# f_dump followed f_root, unless defined
if($f_dump eq $f_dump_def){
  $f_dump=$f_root.".csh";
}

# help
if($help){
    print<<ENDOFTEXT;
make_vega.pl
OTTER reference DB
  -host           char      host of mysql instance ($host)
  -db             char      database ($db)
  -port           num       port ($port)
  -user           char      user ($user)
  -pass           char      passwd

VEGA DB
  -host2          char      host of mysql instance ($host2)
  -db2            char      database ($db2)
  -port2          num       port ($port2)
  -user2          char      user ($user2)
  -pass2          char      passwd

  -vega_set       set[,set] dump datasets listed only (vega set name)
  -sequence_set   set[,set] dump datasets listed only (sequence set name)
  -external                 dump datasets defined as 'external' (vega_set) only

STEP 1 (pipeline)
  -pipe                     create scripts for pipeline dump
  -pipe_root      char      stem for .sql and .log files for ($f_root)
  -pipe_script    file      output file for pipeline dump script ($f_dump)
  -add                      only dump sql to add particular sequence_set

STEP 2 (annotation)
  -filter_annotation        insert option to transfer genes in clones tagged as annotated
  -o              file      output file for transcript script ($opt_o)
  -transform                create sql for chromosome.name and assembly.type changes (optional)
  -p              file      output file for transform sql ($opt_p)
  -exclude_gene_stable_id file  add an exclude list to each gene transfer command

  -root_dir       dir       root directory for script called by csh files ($root_dir)

  -h                        this help
  -help                     perldoc help
  -v                        verbose
  -t                        test

ENDOFTEXT
    exit 0;
}elsif($phelp){
    exec('perldoc', $0);
    exit 0;
}

my %sel_vega_set;
%sel_vega_set=map{$_,1}split(/,/,$sel_vega_set);
my %sel_sequence_set;
%sel_sequence_set=map{$_,1}split(/,/,$sel_sequence_set);

# connect
my $dbh=Bio::EnsEMBL::DBSQL::DBAdaptor->new(
					    -user   => $user,
					    -dbname => $db,
					    -host   => $host,
					    -driver => 'mysql',
					    -host   => $host,
					    -pass   => $pass,
					    );
#if(my $err=&_db_connect(\$dbh,$host,$db,$user,$pass,$port)){
#  print "failed to connect $db: $err\n";
#  exit 0;
#}

# [1] global checks of vega tables for consistency

# fetch vega_set
my $sql = qq{
    SELECT vega_set_id, vega_author_id, vega_type, vega_name
      FROM vega_set
    };
my $sth = $dbh->prepare($sql);
$sth->execute;
my %vega_set;
while (my @row = $sth->fetchrow_array()){
  my $vega_set_id=shift @row;
  $vega_set{$vega_set_id}=[@row];
}

# fetch vega_authors
$sql = qq{
    SELECT vega_author_id, author_email, author_name
      FROM vega_author
    };
my $sth = $dbh->prepare($sql);
$sth->execute;
my %vega_author;
while (my @row = $sth->fetchrow_array()){
  my $vega_author_id=shift @row;
  $vega_author{$vega_author_id}=[@row];
}

my $err=0;
# fetch sequence_set
#  check each vega_set only links to single sequence_set
$sql = qq{
    SELECT assembly_type, vega_set_id
      FROM sequence_set
     WHERE vega_set_id != 0
    };
my $sth = $dbh->prepare($sql);
$sth->execute;
my %vega2ss;
while (my @row = $sth->fetchrow_array()){
  my($assembly_type,$vega_set_id)=@row;
  if($vega2ss{$vega_set_id}){
    $vega2ss{$vega_set_id}.=';';
    $err=1;
    print "FATAL: multiple sequence sets linked to vega_set:\n";
    my $vega_name=$vega_set{$vega_set_id}->[2];
    print "  $vega_name: \'".$vega2ss{$vega_set_id}."\', \'$assembly_type\'\n";
  }
  $vega2ss{$vega_set_id}.=$assembly_type;
}

my %vega_type;
%vega_type=('E'=>'External  ',
	    'I'=>' Internal ',
	    'N'=>'  NoExport',
	    'P'=>'  InProgress',
	    'S'=>'  NoSeqSet');
print "VEGA sets are:\n";
foreach my $vega_set_id (sort {$a<=>$b} keys %vega_set){
  my($vega_author_id, $vega_type, $vega_name)=@{$vega_set{$vega_set_id}};
  my $type=$vega_type{$vega_type};

  my $author;
  if($vega_author{$vega_author_id}){
    $author=$vega_author{$vega_author_id}->[1];
    $author="'$author'";
  }else{
    print "FATAL: no vega_author defined for $vega_name\n";
    $author='UNDEF';
    $err=1;
  }

  my $ass=$vega2ss{$vega_set_id};
  if(!$ass){
    if($vega_type eq 'N'){
      print "  WARN";
    }else{
      print "FATAL";
      $err=1;
    }
    print ": no sequence set for vega_set \'$vega_name\'\n";
  }else{
    $ass="'$ass'";
  }
  printf "  %2d: %-20s (%8s) author %-12s otter_type %s)\n",
  $vega_set_id,$vega_name,$type,$author,$ass;
}

if($err){
  print "\nFatal errors - meta data in $db needs updating\n";
  exit 0;
}
print "\n";

$err=0;

# check that vega_name->assembly_type->chromosome naming looks sensible
print "Checking chromosome label, VEGA name match\n";
$sql = qq{
    SELECT distinct(c.name), a.type
      FROM assembly a, chromosome c, sequence_set ss
     WHERE ss.vega_set_id != 0 
       AND a.chromosome_id=c.chromosome_id
       AND a.type=ss.assembly_type
    };
my $sth = $dbh->prepare($sql);
$sth->execute;
my %ss2chr;
while (my @row = $sth->fetchrow_array()){
  my($chr,$type)=@row;
  $ss2chr{$type}=$chr;
}
foreach my $vega_set_id (sort {$a<=>$b} keys %vega_set){
  my($vega_author_id, $vega_type, $vega_name)=@{$vega_set{$vega_set_id}};
  next if($vega_type eq 'N' || $vega_type eq 'P');
  my $ss=$vega2ss{$vega_set_id};
  my $chr=$ss2chr{$ss};
  if($vega_name=~/^$chr/){
  }else{
    print "  WARN: VEGA name is not prefixed with chromsome:\n";
    print "    name: \'$vega_name\', chromosome: \'$chr\'\n";
  }
}
print "\n";

# [2] dump specific checks
# default is I and E
# -external can modify to E only

# check none of the sequence sets share contigs
# (may not be an issue under scheme 20+)
print "Check that no contigs are reused in VEGA sets\n";
my $not_set="\'N\',\'P\'";
if($ext){
  $not_set="\'N\',\'P\',\'I\'";
}
$sql = qq{
    SELECT ct.name, a.type, a.chr_start, a.chr_end, a.chromosome_id
      FROM assembly a, contig ct, sequence_set ss, vega_set vs
     WHERE ss.vega_set_id = vs.vega_set_id
       AND vs.vega_type not in ($not_set)
       AND a.contig_id=ct.contig_id
       AND a.type=ss.assembly_type
    };
my $sth = $dbh->prepare($sql);
$sth->execute;
my %contig;
my @shared;
my %ss3;
while (my @row = $sth->fetchrow_array()){
  my($contig,$type,$chst,$ched,$chr_id)=@row;
  $contig{$contig}->{$type}=[$chst,$ched];
  if($ss3{$type}){
    my($chst2,$ched2)=@{$ss3{$type}};
    if($chst2<$chst){$chst=$chst2;}
    if($ched2>$ched){$ched=$ched2;}
  }
  $ss3{$type}=[$chst,$ched,$chr_id];
}
my %dcontig;
foreach my $contig (keys %contig){
  if(scalar(keys %{$contig{$contig}})>1){
    foreach my $type (keys %{$contig{$contig}}){
      my($chst,$ched)=@{$contig{$contig}->{$type}};
      $dcontig{$type}->{$contig}=[$chst,$ched];
    }
  }
}
my @shared;
my %ucontig;
foreach my $type (sort keys %dcontig){
  foreach my $contig (sort {$dcontig{$type}->{$a}->[0]<=>$dcontig{$type}->{$b}->[0]} keys %{$dcontig{$type}}){
    # only process each contig once
    next if $ucontig{$contig};
    $ucontig{$contig}=1;
    #print "P $type:$contig\n";

    my($chst,$ched)=@{$dcontig{$type}->{$contig}};

    # look for a match for $type
    my $match=0;
    my $mxi=scalar(@shared);
    for(my $i=0;$i<$mxi;$i++){
      if($shared[$i]->{$type}){
	my($chst2,$ched2,@contigs)=@{$shared[$i]->{$type}};
	#print "   test $i $chst2-$ched2 $chst\n";
	if($chst==$ched2+1){
	  $shared[$i]->{$type}=[$chst2,$ched,@contigs,$contig];
	  $match=1;
	  $mxi=$i;
	  last;
	}
      }
    }
    if($match){
      #print " old $mxi [$chst-$ched]\n";
    }else{
      $shared[$mxi]->{$type}=[$chst,$ched,$contig];
      #print " new $mxi [$chst-$ched]\n";
    }
    # save match for other $types
    foreach my $type2 (sort keys %{$contig{$contig}}){
      next if $type eq $type2;
      my($chst,$ched)=@{$contig{$contig}->{$type2}};
      if($shared[$mxi]->{$type2}){
	my($chst2,$ched2,@contigs)=@{$shared[$mxi]->{$type2}};
	if($chst=$ched2+1){
	  $shared[$mxi]->{$type2}=[$chst2,$ched,@contigs,$contig];
	  #print "   extended $type2 $mxi [$chst2-$ched]\n";
	}
      }else{
	$shared[$mxi]->{$type2}=[$chst,$ched,$contig];
	#print "   new $type2 $mxi [$chst-$ched]\n";
      }
    }
  }
}
# report
my $mxi=scalar(@shared);
if($mxi>0){
  my $nr=$mxi+1;
  print "WARN: Following $nr regions are shared between VEGA sets\n";
  my $ri=0;
  for(my $i=0;$i<$mxi;$i++){
    $ri++;
    print " REGION $ri:\n";
    foreach my $type (sort keys %{$shared[$i]}){
      my($chst,$ched,@contigs)=@{$shared[$i]->{$type}};
      my $nc=scalar(@contigs);
      print "  $type:$chst-$ched $nc contigs\n";
      print "    ".join(',',@contigs)."\n" if $opt_v;
    }
  }
}
print "\n";

my %sset;
my %vset;
my %vega_subset;
foreach my $vega_set_id (sort {$a<=>$b} keys %vega_set){
  my($vega_author_id, $vega_type, $vega_name)=@{$vega_set{$vega_set_id}};

  # filter out sets we don't want to consider
  next if ($vega_type eq 'N' || $vega_type eq 'P');
  next if ($ext && $vega_type eq 'I');
  next if ($sel_vega_set && !$sel_vega_set{$vega_name});
  my $ss=$vega2ss{$vega_set_id};
  next if ($sel_sequence_set && !$sel_sequence_set{$ss});
  $sset{$ss}=1;
  $vset{$vega_name}=1;
  # save this selection to reuse
  $vega_subset{$vega_set_id}=1;
}
print "Selected sets are ".join(',',(sort {$a<=>$b} keys %vega_subset))."\n\n";
my $flag;
if($sel_vega_set){
  foreach my $sset (keys %sel_vega_set){
    if(!$vset{$sset}){
      print "ERROR: selected vega_set \'$sset\' not found\n";
      $flag=1;
    }
  }
}
if($sel_sequence_set){
  foreach my $sset (keys %sel_sequence_set){
    if(!$sset{$sset}){
      print "ERROR: selected sequence_set \'$sset\' not found\n";
      $flag=1;
    }
  }
}
exit 0 if $flag;

# create script to dump pipeline
if($pipe){
  my $tadd;
  if($add){$tadd='-add';}
  my $p_db=Bio::Otter::Lace::SatelliteDB::get_options_for_key($dbh,'pipeline_db');
  my $sset=join(',',(sort keys %sset));
  open(OUT,">$f_dump") || die "cannot open $opt_o";
  print OUT "#!/bin/csh -f\n\n#\n# commands autogenerated by make_vega.pl\n#\n\n";
  print OUT "source $root_dir/src/source/source9pipeline\n\n";
  print OUT "$root_dir/src/lace_local_admin/scripts/mysqlcopy_sequence_set.pl -set $sset -o $f_root.sql -i $root_dir/src/trunk/ensembl-otter/sql/otter.sql -host ".$p_db->{'-HOST'}." -port ".$p_db->{'-PORT'}." -user ".$p_db->{'-USER'}." -db ".$p_db->{'-DBNAME'}." $tadd > & ! $f_root.log\n";
  close(OUT);
  print "Wrote command for dumping pipeline database\n";
  exit 0;
}

if($opt_t || $err){
  if($err){
    print "\nFatal errors - meta data in $db needs updating\n";
  }
  exit 0;
}

my $dbh2;
my %ss2;
if(!$list){

  if(my $err=&_db_connect(\$dbh2,$host2,$db2,$user2,$pass2,$port2)){
    print "failed to connect $db2: $err\n";
    exit 0;
  }

  # check that target dataset has no genes (expect it to be empty)
  $sql = qq{
    SELECT count(*)
      FROM gene
    };
  my $sth = $dbh2->prepare($sql);
  $sth->execute;
  while (my @row = $sth->fetchrow_array()){
    if($row[0]>0){
      $err=1 unless $opt_I;
      print "WARN target database already contains ".$row[0]." genes\n";
    }
  }

  # check that target database has all sequence_sets to be transfered
  $sql = qq{
    SELECT distinct type
      FROM assembly
    };
  my $sth = $dbh2->prepare($sql);
  $sth->execute;
  while (my @row = $sth->fetchrow_array()){
    my $as=$row[0];
    $ss2{$row[0]}=1;
  }
  $sql = qq{
    SELECT c.name,min(a.chr_start),max(a.chr_end),c.chromosome_id
      FROM assembly a, chromosome c
      WHERE a.chromosome_id=c.chromosome_id
      AND a.type= ?
      GROUP BY a.type
    };
  my $sth = $dbh2->prepare($sql);
  foreach my $vega_set_id (sort {$a<=>$b} keys %vega_subset){
    my($vega_author_id, $vega_type, $vega_name)=@{$vega_set{$vega_set_id}};
    my $ss=$vega2ss{$vega_set_id};
    my $chr=$ss2chr{$ss};
    my $ss=$vega2ss{$vega_set_id};
    # skip anything not in set list
    if($ss2{$ss}){
      $sth->execute($ss);
      while (my @row = $sth->fetchrow_array()){
	my($chr2,$chr_st,$chr_ed,$chr_id)=@row;
	if($chr2 ne $chr){
	  print "FATAL target database chr mismatch ($chr,$chr2) $ss\n";
	  $err=1;
	}else{
	  $ss2{$ss}=[$chr_st,$chr_ed,$chr_id];
	}
      }
    }else{
      $err=1;
      print "FATAL target database missing sequence_set \'$ss\'\n";
    }
  }
  
  if(!$pass2){
    print "FATAL: need write access to $db2 - must give password as -pass2\n";
    $err=1;
  }
  
  if($err){
    if($err){
      print "\nFatal errors checking target database\n";
    }
    exit 0;
  }
}

# build lists
my $type_string;
my %chr_id;
my $filter_text;
if($filter_annotation){$filter_text='-filter_annotation';}
if(!$vega_internal){$filter_text.=" -filter_gd -filter_for_vega";}
if($exclude_gene_stable_id){$filter_text.=" -exclude_gene_stable_id $exclude_gene_stable_id";}

# loop over valid sequence sets and write transfer commands
open(OUT,">$opt_o") || die "cannot open $opt_o";
print OUT "#!/bin/csh -f\n\n#\n# commands autogenerated by make_vega.pl\n#\n\n";
print OUT "source $root_dir/src/source/source9pipeline\n\n";
foreach my $vega_set_id (sort {$a<=>$b} keys %vega_subset){
  my($vega_author_id, $vega_type, $vega_name)=@{$vega_set{$vega_set_id}};
  print "Wrote commands for transfering \'$vega_name\'\n";
  my $listcom;
  if($list){
    $listcom="-l gsi_".$vega_name.".lis";
  }
  my $ss=$vega2ss{$vega_set_id};
  my $chr=$ss2chr{$ss};
  my($chr_st,$chr_ed,$chr_id);
  # should clean this bit up - check same...
  if(!$list){
    ($chr_st,$chr_ed,$chr_id)=@{$ss2{$ss}};
  }else{
    ($chr_st,$chr_ed,$chr_id)=@{$ss3{$ss}};
  }
  if($type_string){$type_string.=',';}
  $type_string.="\'$ss\'";
  $chr_id{$chr_id}=1;
  print OUT "$root_dir/src/trunk/ensembl-otter/scripts/conversion/assembly/transfer_annotation.pl -host $host -user $user -pass $pass -port $port -dbname $db -c_host $host -c_user $user -c_pass $pass -c_port $port -c_dbname $db -t_host $host2 -t_user $user2 -t_pass $pass2 -t_port $port2 -t_dbname $db2 -chr $chr -chrstart $chr_st -chrend $chr_ed -path $ss -c_path $ss -t_path $ss -filter_obs $filter_text $listcom >&! ogt_".$vega_name.".log \n";
  print OUT "$root_dir/src/trunk/ensembl-otter/scripts/conversion/assembly/transfer_clone_annotation.pl -host $host -user $user -port $port -dbname $db -t_host $host2 -t_user $user2 -t_pass $pass2 -t_port $port2 -t_dbname $db2 -t_path $ss > ! oct_".$vega_name."_sf.log\n" unless $list;
}
print "\n";
close(OUT);

if($transform){

  # loop over valid sequence sets and write transform sql commands
  open(OUT,">$opt_p") || die "cannot open $opt_p";
  print OUT "#\n# sql autogenerated by make_vega.pl\n#\n\n";

  # delete orphan chromosomes, assemblies

  my $chrid_string=join(',',(keys %chr_id));
  print OUT "# remove unneeded assembly entries\n";
  print OUT "delete from assembly where type not in ($type_string);\n\n";
  print OUT "# remove unneeded chrosome entries\n";

  # create new chromosomes with correct lengths and link assembly table to them
  #print OUT "delete from chromosome where chromosome_id not in ($chrid_string);\n\n";
  print OUT "delete from chromosome;\n\n";
  my $ichr=0;
  my %used_authors;
  foreach my $vega_set_id (sort {$a<=>$b} keys %vega_subset){
    my($vega_author_id, $vega_type, $vega_name)=@{$vega_set{$vega_set_id}};
    $used_authors{$vega_author_id}=1;
    my $ss=$vega2ss{$vega_set_id};
    my($chr_st,$chr_ed,$chr_id)=@{$ss2{$ss}};
    $ichr++;
    print OUT "insert into chromosome values($ichr,\'$vega_name\',$chr_ed);\n";
    print OUT "update assembly set chromosome_id=$ichr where type=\'$ss\';\n";
  }
  print OUT "update assembly set type=\'VEGA\';\n";

  # fix authors
  print OUT "delete from author;\n\n";
  foreach my $vega_author_id (sort keys %used_authors){
    my($author_email,$author_name)=@{$vega_author{$vega_author_id}};
    print OUT "insert into author values ($vega_author_id,\'$author_email\',\'$author_name\');\n";
  }
}

# delete unwanted tables
# (should come from another meta table?)

# insert meta information
# (should come from another meta table?)

close(OUT);

print "Wrote files ok\n";

#$dbh->do(qq{});

#$dbh->disconnect();
#$dbh2->disconnect() unless $list;

exit 0;

# connect to db with error handling
sub _db_connect{
  my($rdbh,$host,$database,$user,$pass,$port)=@_;
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

=head1 

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

=item 

B<th> released first version

=back

=head1 BUGS

=head1 AUTHOR

B<Tim Hubbard> Email th@sanger.ac.uk

=cut
