#!/usr/local/bin/perl

# Compare full set of gene_stable_ids in 2 databases

use strict;
use Getopt::Long;
use Bio::EnsEMBL::DBSQL::DBAdaptor;
use Bio::Otter::DBSQL::DBAdaptor;

# hard wired
my $driver="mysql";

my $port=3306;
my $pass;
my $host='humsrv1';
my $user='ensro';
my $dbname='otter_human';

my $port2=3309;
my $pass2;
my $host2='ecs3h';
my $user2='ensro';
my $dbname2='vega_homo_sapiens_core_5_0';
my $gomi;

my $help;
my $phelp;
my $opt_v;

# fixed parameters

$Getopt::Long::ignorecase=0;

GetOptions(
	   'port:s', \$port,
	   'pass:s', \$pass,
	   'host:s', \$host,
	   'user:s', \$user,
	   'db:s',   \$dbname,

	   'port2:s', \$port2,
	   'pass2:s', \$pass2,
	   'host2:s', \$host2,
	   'user2:s', \$user2,
	   'db2:s',   \$dbname2,

	   'help',   \$phelp,
	   'h',      \$help,
	   'v',      \$opt_v,

	   );

# help
if($phelp){
    exec('perldoc', $0);
    exit 0;
}
if($help){
    print<<ENDOFTEXT;
compare_gene_id.pl

DB1
  -host           host    host of mysql instance ($host)
  -db             dbname  database ($dbname)
  -port           port    port ($port)
  -user           user    user ($user)
  -pass           pass    password 

DB2
  -host2          host    host of mysql instance ($host2)
  -db2            dbname  database ($dbname2)
  -port2          port    port ($port2)
  -user2          user    user ($user2)
  -pass2          pass    password 

  -h                      this help
  -help                   perldoc help
  -v                      verbose
ENDOFTEXT
    exit 0;
}

my $dbh = new Bio::EnsEMBL::DBSQL::DBConnection(-host => $host,
						-user => $user,
						-pass => $pass,
						-port => $port,
						-dbname => $dbname,
						-driver=>'mysql');

my $dbh2 = new Bio::EnsEMBL::DBSQL::DBConnection(-host => $host2,
						-user => $user2,
						-pass => $pass2,
						-port => $port2,
						-dbname => $dbname2,
						-driver=>'mysql');


my $sdb = new Bio::Otter::DBSQL::DBAdaptor(-host => $host,
                                           -user => $user,
                                           -pass => $pass,
                                           -port => $port,
                                           -dbname => $dbname);
my $aga = $sdb->get_GeneAdaptor;

my $sql=qq{SELECT gsi1.stable_id, gsi1.version, g.type
	     FROM gene g, gene_stable_id gsi1 
	LEFT JOIN gene_stable_id gsi2
               ON gsi1.stable_id = gsi2.stable_id
              AND gsi1.version<gsi2.version
	    WHERE gsi2.stable_id is NULL
              AND gsi1.gene_id = g.gene_id
	    };
my $sth = $dbh->prepare($sql);
$sth->execute();
my %gsi;
my %type1;
while (my @row = $sth->fetchrow_array()){
  my($gsi,$version,$type)=@row;
  $gsi{$gsi}=[$version,$type];
  $type1{$type}++;
}

my $sql=qq{SELECT gsi1.stable_id, gsi1.version, g.type
	     FROM gene g, gene_stable_id gsi1 
	LEFT JOIN gene_stable_id gsi2
               ON gsi1.stable_id = gsi2.stable_id
              AND gsi1.version<gsi2.version
	    WHERE gsi2.stable_id is NULL
              AND gsi1.gene_id = g.gene_id
	    };
my $sth = $dbh2->prepare($sql);
$sth->execute();
my $nm=0;
my %nm;
my $no=0;
my %no;
my $nt=0;
my $np=0;
my $nn=0;
my $ns=0;
my $n=0;
my %type2;
while (my @row = $sth->fetchrow_array()){
  my($gsi,$version,$type)=@row;
  $type2{$type}++;
  $n++;
  if($gsi{$gsi}){
    my($version2,$type2)=@{$gsi{$gsi}};
    if($type2 eq 'obsolete'){
      $no++;
      $no{$gsi}->[0]=$type;

      # find what type this gene is on
      my $sql=qq{SELECT distinct a.type
	     FROM gene_stable_id gsi, transcript t, exon_transcript et, exon e,
		  assembly a
	    WHERE gsi.gene_id=t.gene_id
	      AND t.transcript_id=et.transcript_id
	      AND et.exon_id=e.exon_id
	      AND e.contig_id=a.contig_id
              AND gsi.stable_id=?
	    };
      my $sth = $dbh->prepare($sql);
      $sth->execute($gsi);
      while (my @row = $sth->fetchrow_array()){
	next if $row[0]=~/gomi/;
	push(@{$no{$gsi}->[1]},$row[0]);
      }
    }elsif($type2 ne $type){
      $nt++;
    }elsif($version<$version2){
      $np++;
    }elsif($version2<$version){
      $nn++;
    }else{
      $ns++;
    }
  }else{
    $nm++;
    $nm{$gsi}=$type;
  }
}
print scalar(keys %gsi)." genes in $dbname\n";
print "$n genes in $dbname2\n";
print "$nm idenfiers have vanished\n";
foreach my $gsi (sort keys %nm){print "  $gsi:".$nm{$gsi}."\n";}
print "$no idenfiers are now obselete\n";
foreach my $gsi (sort keys %no){print "  $gsi:".$no{$gsi}->[0]." ".
				    join(',',@{$no{$gsi}->[1]})."\n";}
print "$np have more recent versions\n";
print "$nn have older versions\n";
print "$ns have idenfical versions\n\n";

my %type;
%type=%type1;
foreach my $type (keys %type2){
  $type{$type}=1;
}
foreach my $type (sort keys %type){
  printf "%-25s %5d %5d\n",$type,$type1{$type},$type2{$type};
}

exit 0;

__END__

=pod

=head1 patch24.pl

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

=item 16-JAN-2003

B<th> released first version

=back

=head1 BUGS

=head1 AUTHOR

B<Tim Hubbard> Email th@sanger.ac.uk

=cut
