#!/usr/local/bin/perl

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
my $port=3306;
my $pass;
my $host='humsrv1';
my $user='ensro';
my $db='otter_human';
my $help;
my $phelp;
my $opt_v;
my $opt_i='';
my $opt_o='check_genes.lis';
my $cache_file='check_genes.cache';
my $make_cache;
my $opt_c='';
my $opt_t;

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
	   'c:s',  \$opt_c,
	   'make_cache',\$make_cache,
	   't:s',  \$opt_t,
	   );

# help
if($phelp){
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
  -o              file      output file ($opt_o)
  -c              char      chromosome ($opt_c)
  -make_cache               make cache file
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
  my $sth=$dbh->prepare("select a.contig_id, c.name, a.type, a.chr_start, a.chr_end, a.contig_start, a.contig_end, a.contig_ori from chromosome c, assembly a, sequence_set ss, vega_set vs where a.chromosome_id=c.chromosome_id and a.type=ss.assembly_type and ss.vega_set_id=vs.vega_set_id and vs.vega_type != 'N'");
  $sth->execute;
  my $n=0;
  while (my @row = $sth->fetchrow_array()){
    my $cid=shift @row;
    $a{$cid}=[@row];
    $n++;
  }
  print "$n contigs read from assembly\n";

  # get exons of current genes
  my $sth=$dbh->prepare("select gsi1.stable_id,gn.name,g.type,tsi.stable_id,ti.name,et.rank,e.exon_id,e.contig_id,e.contig_start,e.contig_end from exon e, exon_transcript et, transcript t, current_gene_info cgi, gene_stable_id gsi1, gene_name gn, gene g, transcript_stable_id tsi, current_transcript_info cti, transcript_info ti left join gene_stable_id gsi2 on (gsi1.stable_id=gsi2.stable_id and gsi1.version<gsi2.version) where gsi2.stable_id IS NULL and cgi.gene_stable_id=gsi1.stable_id and cgi.gene_info_id=gn.gene_info_id and gsi1.gene_id=g.gene_id and g.gene_id=t.gene_id and t.transcript_id=tsi.transcript_id and tsi.stable_id=cti.transcript_stable_id and cti.transcript_info_id=ti.transcript_info_id and t.transcript_id=et.transcript_id and et.exon_id=e.exon_id and e.contig_id");
  $sth->execute;
  my $nexclude=0;
  my %excluded_gsi;
  open(OUT,">$cache_file") || die "cannot open cache file $cache_file";
  while (my @row = $sth->fetchrow_array()){
    $n++;

    # transform to chr coords
    my($gsi,$gn,$gt,$tsi,$tn,$erank,$eid,$ecid,$est,$eed)=@row;
    if($a{$ecid}){
      if($excluded_gsi{$gsi}){
	print "WARN $gsi already had exon excluded: ".$excluded_gsi{$gsi}."\n";
      }

      my($cname,$atype,$acst,$aced,$ast,$aed,$ao)=@{$a{$ecid}};
      my $ecst;
      my $eced;
      if($ao==1){
	$ecst=$acst+$est-$ast;
	$eced=$aced+$eed-$ast;
      }else{
	$ecst=$acst-$est+$aed;
	$eced=$aced-$eed+$aed;
      }
      # constant direction - easier later
      if($ecst>$eced){
	my $t=$ecst;
	$ecst=$eced;
	$eced=$t;
      }
      my @row2=($gsi,$gn,$gt,$tsi,$tn,$erank,$eid,$ecst,$eced,$cname,$atype);
      print OUT join("\t",@row2)."\n";
    }else{
      $nexclude++;
      $excluded_gsi{$gsi}=join(',',@row);
    }
    last if ($opt_t && $n>=$opt_t);
  }
  close(OUT);
  $dbh->disconnect();
  print "wrote $n records to cache file $cache_file\n";
  print "wrote $nexclude exons ignored as not in selected assembly\n";
  exit 0;
}

my %gsi;
my $n=0;
open(IN,"$cache_file") || die "cannot open $opt_i";
while(<IN>){
  chomp;
  my($gsi,$gii,$gn,$chr,$atype,$gtype)=split(/\t/);
  $n++;
}
close(IN);
print "$n name relationships read\n";

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
