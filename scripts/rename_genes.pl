#!/usr/bin/env perl
# Copyright [2018-2020] EMBL-European Bioinformatics Institute
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


# script to take a list of HUGO names current gene labels and write
# sql required to change them.  ONLY SUITABLE FOR VEGA DATABASEs which
# only one assembly for each clone and the most recent version of each
# gene.

use strict;
use Getopt::Long;
use DBI;
use Sys::Hostname;

# hard wired
my $driver="mysql";
my $port=3352;
my $pass;
my $host='ecs4';
my $user='ensadmin';
my $db='human_vega5c_copy';
my $help;
my $phelp;
my $opt_v;
my $opt_i='nomnclature_6_2.txt';
my $opt_o='rename_genes.sql';
my $opt_q='gene_xref_update.lis';
my $opt_p='duplicate_genes.lis';
my $opt_c='6';
my $opt_C='6_PG,6_CX';
my $cache_file='rename_genes.cache';
my $cache;

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
	   'i:s',  \$opt_i,
	   'o:s',  \$opt_o,
	   'p:s',  \$opt_p,
	   'q:s',  \$opt_q,
	   'c:s',  \$opt_c,
	   'C:s',  \$opt_C,
	   'cache',\$cache,
	   );

# help
if($phelp || !$opt_c){
  exec('perldoc', $0);
  exit 0;
}
if($help){
  print<<ENDOFTEXT;
rename_genes.pl
  -host           char      host of mysql instance ($host)
  -db             char      database ($db)
  -port           num       port ($port)
  -user           char      user ($user)
  -pass           char      passwd

  -h                        this help
  -help                     perldoc help
  -v                        verbose
  -i              file      input file of names ($opt_i)
  -o              file      sql output file ($opt_o)
  -p              file      duplicate gene list output file ($opt_p)
  -c              char      chromosome ($opt_c)
  -cache                    load db data from cache file
ENDOFTEXT
    exit 0;
}

# allowed list of haplotype chromosomes
my %hap;
%hap=map{$_,1}split(/,/,$opt_C);

# read file - expect it to be new<tab>old
my %old2new;
my %new2old;
my $n=0;
open(IN,"$opt_i") || die "cannot open $opt_i";
while(<IN>){
  if(/^\s*(\S+)\s+(\S+)\s*$/){
    my($new,$old)=($1,$2);
    $old2new{$old}=$new;
    $new2old{$new}=$old;
    $n++;
  }
}
close(IN);
print "$n name changes read\n";

# connect
my $dbh;
if(my $err=&_db_connect(\$dbh,$host,$db,$user,$pass)){
  print "failed to connect $err\n";
  exit 0;
}

my %gn;
my %gii;
my $n=0;
if($cache){
  open(IN,"$cache_file") || die "cannot open $opt_i";
  while(<IN>){
    chomp;
    my($gsi,$gii,$gn,$chr,$atype,$gtype)=split(/\t/);
    $gn{$gn}=[$gsi,$gii,$chr,$atype,$gtype];
    $gii{$gii}=$gn;
    $n++;
  }
  close(IN);
  print "$n name relationships read\n";
}else{
  my $sth=$dbh->prepare("select distinct(gsi.stable_id),cgi.gene_info_id,gn.name,c.name,a.type,g.type from chromosome c, assembly a, contig ct, exon e, exon_transcript et, transcript t, current_gene_info cgi, gene_stable_id gsi, gene_name gn, gene g where cgi.gene_stable_id=gsi.stable_id and cgi.gene_info_id=gn.gene_info_id and gsi.gene_id=g.gene_id and g.gene_id=t.gene_id and t.transcript_id=et.transcript_id and et.exon_id=e.exon_id and e.contig_id=ct.contig_id and ct.contig_id=a.contig_id and a.chromosome_id=c.chromosome_id");
  $sth->execute;
  my $ndd=0;
  my $nds=0;
  open(OUT,">$opt_p") || die "cannot open $opt_p";
  while (my @row = $sth->fetchrow_array()){
    my($gsi,$gii,$gn,$chr,$atype,$gtype)=@row;
    if($gn{$gn}){
      my($gsi2,$gii2,$chr2,$atype2,$gtype2)=@{$gn{$gn}};
      # save on this chromosome if choice (avoid other haplotypes)
      # else keep old one
      if($chr eq $opt_c){
	# want to keep higher OTT if chr are same
	my $ngsi=$gsi;
	my $ngsi2=$gsi2;
	$ngsi=~s/^OTTHUMG//;
	$ngsi2=~s/^OTTHUMG//;
	if($chr2 ne $chr || $ngsi>$ngsi2){
	  $gn{$gn}=[$gsi,$gii,$chr,$atype,$gtype];
	}
      }
      if($chr ne $chr2 || $atype ne $atype2){
	print "warn - duplicate gene_name $gsi:$gii:$chr:$atype:$gtype ($gn) diff chr/ass\n";
	print "                           $gsi2:$gii2:$chr2:$atype2:$gtype2\n";
	$ndd++;
      }else{
	print "WARN - duplicate gene_name $gsi:$gii:$chr:$atype:$gtype ($gn) SAME chr/ass\n";
	print "                           $gsi2:$gii2:$chr2:$atype2:$gtype2\n";
	print OUT "$gsi $gsi2 $chr $atype\n";
	$nds++;
      }
    }else{
      $gn{$gn}=[$gsi,$gii,$chr,$atype,$gtype];
    }
  }
  close(OUT);
  print "$ndd duplicate genes on different chr/ass\n";
  print "$nds duplicate genes on SAME chr/ass\n";
  # save cache file
  open(OUT,">$cache_file") || die "cannot open $cache_file";
  foreach my $gn (keys %gn){
    my($gsi,$gii,$chr,$atype,$gtype)=@{$gn{$gn}};
    print OUT "$gsi\t$gii\t$gn\t$chr\t$atype\t$gtype\n";
    $n++;
  }
  close(OUT);
  print "$n name relationships read\n";
  exit 0;
}

# build gii->gn mapping
print "\ngene_info_id -> gene_name mapping:\n";
my %gii2gn;
my $n=0;
foreach my $gn (keys %gn){
  my($gsi,$gii,$chr,$atype,$gtype)=@{$gn{$gn}};
  if($gii2gn{$gii}){
    my $gn2=$gii2gn{$gii};
    print "WARN multiple gene_name for $gii ($gn, $gn2)\n";
    $n++;
  }
  $gii2gn{$gii}=$gn;
}
print "$n duplicate gene_name for gene_info_ids\n";

# get gene_synonym table (no cache as simple query)
my %gs;
my $n=0;
my $nd=0;
my $sth=$dbh->prepare("select name,gene_info_id from gene_synonym");
$sth->execute;
while (my @row = $sth->fetchrow_array()){
  my($sn,$gii)=@row;
  if($gs{$sn}){
    my $gii2=$gs{$sn};
    print "warn $sn is synonym for multiple gene_info_ids ($gii, $gii2)\n" if $opt_v;
    # if there are multiple
    # warn if both in cache
    if($gii{$gii} && $gii{$gii2}){
      print "WARN $sn is synonym for $gii ($gii{$gii}) and $gii2 ($gii{$gii2})\n";
    }
    # keep any that are in the cache
    if($gii{$gii}){
      $gs{$sn}=$gii;
    }
    $nd++;
  }else{
    $gs{$sn}=$gii;
  }
  $n++;
}
print "read $n gene_synonyms ($nd duplicates)\n\n";

# out file for writing SQL changes:
open(OUT,">$opt_o") || die "cannot open $opt_o";
open(OUT2,">$opt_q") || die "cannot open $opt_q";

print "Check existing naming\n";
my %skip;
# if new name already there, don't need to change, but check for old too
my $nexist=0;
my $ne1=0;
my $ne2=0;
my $ne3=0;
my $ne4=0;
my $nok1=0;
my $nhap=0;
foreach my $gn (keys %gn){
  my($gsi,$gii,$chr,$atype,$gtype)=@{$gn{$gn}};
  # ignore if it's in a different haplotype
  if($new2old{$gn} && $hap{$chr}){
    print "$gn already a gene name in a different haplotype\n";
    $nhap++;
  }elsif($new2old{$gn}){
    my $old=$new2old{$gn};
    $skip{$old}=1;
    $nexist++;
    print "$gn already a gene name - no change from $old required\n";
    # expect it to be on this chromsome
    if($chr ne $opt_c){
      print "  WARN unexpected chromosome $chr ($opt_c) for $gn\n";
      $ne1++;
      next;
    }
    # don't expect old name to also be a gene_name\n";
    if($gn{$old}){
      my($gsi2,$gii2,$chr2)=@{$gn{$old}};
      print "  WARN old name also found: $old $gsi2:$chr2\n";
      $ne2++;
      next;
    }
    # check if old name has been stored as a gene synonym, and if so
    # if it points to the new name as expected..
    if($gs{$old}){
      my $gii2=$gs{$old};
      if($gii2 ne $gii){
	print "  WARN $old is listed as a synonym, but for a different gene\n";
	$ne3++;
      }else{
	$nok1++;
      }
    }else{
      print "  WARN $old is not listed as a synonym for $gn - writing change\n";
      print OUT "insert into gene_synonym values (NULL,'$old',$gii);\n";
      $ne4++;
    }
  }
}
print "$nexist names already changed\n";
print "  $ne1 names used on other chromsomes!\n";
print "  $ne2 old name still exists!\n";
print "  $ne3 old names listed as synonym for different gene!\n";
print "  $ne4 old names not listed as synonym!\n";
print "  $nok1 listed correctly as synonym\n";
print "  $nhap listed in different haplotype\n\n";

# go through list, avoiding ones already skipped
my $no=0;
my $nc=0;
foreach my $old (keys %old2new){
  next if($skip{$old});
  my $new=$old2new{$old};
  if($gn{$old}){
    my($gsi,$gii,$chr,$atype,$gtype)=@{$gn{$old}};
    print OUT "insert into gene_synonym values (NULL,'$old',$gii);\n";
    print OUT "update gene_name set name='$new' where gene_info_id=$gii;\n";
    print OUT2 "$gsi\n";
    $nc++;
  }else{
    print "Warn: Old gene name $old not found in db - New gene name $new not used\n";
    $no++;
  }
}
print "$no old gene names not found\n";
print "$nc gene names changes proposed\n";

close(OUT);
close(OUT2);

$dbh->disconnect();

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
