#!/usr/local/bin/perl

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
my $opt_e;
my $opt_I;

my $opt_o='vega_transfer.csh';
my $opt_p='vega_transform.sql';

$Getopt::Long::ignorecase=0;

GetOptions(
	   'port:s', \$port,
	   'pass:s', \$pass,
	   'host:s', \$host,
	   'user:s', \$user,
	   'db:s', \$db,

	   'port2:s', \$port2,
	   'pass2:s', \$pass2,
	   'host2:s', \$host2,
	   'user2:s', \$user2,
	   'db2:s', \$db2,

	   't', \$opt_t,
	   'e', \$opt_e,

	   'o:s', \$opt_o,
	   'o:s', \$opt_p,

	   'help', \$phelp,
	   'h', \$help,
	   'v', \$opt_v,
	   'I', \$opt_I,
	   );

# help
if($help){
    print<<ENDOFTEXT;
split_gene.pl
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

  -t                        test
  -e                        dump external datasets only

  -o              file      output file for transcript script ($opt_o)
  -p              file      output file for transform sql ($opt_p)

  -h                        this help
  -help                     perldoc help
  -v                        verbose

ENDOFTEXT
    exit 0;
}elsif($phelp){
    exec('perldoc', $0);
    exit 0;
}

# connect
my $dbh;
if(my $err=&_db_connect(\$dbh,$host,$db,$user,$pass,$port)){
  print "failed to connect $db: $err\n";
  exit 0;
}

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
    my $vega_name=@{$vega_set{$vega_set_id}}->[2];
    print "  $vega_name: \'".$vega2ss{$vega_set_id}."\', \'$assembly_type\'\n";
  }
  $vega2ss{$vega_set_id}.=$assembly_type;
}

my %vega_type;
%vega_type=('E'=>'External  ',
	    'I'=>' Internal ',
	    'N'=>'  NoExport',
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
  next if $vega_type eq 'N';
  my $ss=$vega2ss{$vega_set_id};
  my $chr=$ss2chr{$ss};
  if($vega_name=~/^$chr/){
  }else{
    print "  WARN: VEGA name is not prefixed with chromsome:\n";
    print "    name: \'$vega_name\', chromosome: \'$chr\'\n";
  }
}
print "\n";

# check none of the sequence sets share contigs
# (may not be an issue under scheme 20+)
print "Check that no contigs are reused in VEGA sets\n";
$sql = qq{
    SELECT c.name, a.type
      FROM assembly a, contig c, sequence_set ss, vega_set vs
     WHERE ss.vega_set_id = vs.vega_set_id
       AND vs.vega_type != 'N'
       AND a.contig_id=c.contig_id
       AND a.type=ss.assembly_type
    };
my $sth = $dbh->prepare($sql);
$sth->execute;
my %contig;
while (my @row = $sth->fetchrow_array()){
  my($contig,$type)=@row;
  if($contig{$contig}){
    print "FATAL contig shared between two VEGA sets\n";
    print "  $contig: $contig{$contig}, $type\n";
  }else{
    $contig{$contig}=$type;
  }
}
print "\n";

if($opt_t || $err){
  if($err){
    print "\nFatal errors - meta data in $db needs updating\n";
  }
  exit 0;
}

my $dbh2;
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
  SELECT assembly_type
    FROM sequence_set
  };
my $sth = $dbh2->prepare($sql);
$sth->execute;
my %ss2;
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
foreach my $vega_set_id (sort {$a<=>$b} keys %vega_set){
  my($vega_author_id, $vega_type, $vega_name)=@{$vega_set{$vega_set_id}};
  next if $vega_type eq 'N';
  my $ss=$vega2ss{$vega_set_id};
  my $chr=$ss2chr{$ss};
  my $ss=$vega2ss{$vega_set_id};
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
    print "FATAL target database missing sequence_set $ss\n";
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

# build lists
my $type_string;
my %chr_id;

# loop over valid sequence sets and write transfer commands
open(OUT,">$opt_o") || die "cannot open $opt_o";
print OUT "#!/bin/csh -f\n\n#\n# commands autogenerated by make_vega.pl\n#\n\n";
print OUT "source ../../../src/source/source9pipeline\n\n";
foreach my $vega_set_id (sort {$a<=>$b} keys %vega_set){
  my($vega_author_id, $vega_type, $vega_name)=@{$vega_set{$vega_set_id}};
  next if $vega_type eq 'N';
  my $ss=$vega2ss{$vega_set_id};
  my $chr=$ss2chr{$ss};
  my($chr_st,$chr_ed,$chr_id)=@{$ss2{$ss}};
  if($type_string){$type_string.=',';}
  $type_string.="\'$ss\'";
  $chr_id{$chr_id}=1;
  print OUT "../../../src/trunk/ensembl-otter/scripts/conversion/assembly/transfer_annotation.pl -host $host -user $user -pass $pass -port $port -dbname $db -c_host $host -c_user $user -c_pass $pass -c_port $port -c_dbname $db -t_host $host2 -t_user $user2 -t_pass $pass2 -t_port $port2 -t_dbname $db2 -chr $chr -chrstart $chr_st -chrend $chr_ed -path $ss -c_path $ss -t_path $ss -filter_gd -filter_obs >&! ogt_".$vega_name.".log \n";
  print OUT "../../../src/trunk/ensembl-otter/scripts/conversion/assembly/transfer_clone_annotation.pl -host $host -user $user -port $port -dbname $db -t_host $host2 -t_user $user2 -t_pass $pass2 -t_port $port2 -t_dbname $db2 -t_path $ss > ! oct_".$vega_name."_sf.log\n";
}
print "\n";
close(OUT);

# loop over valid sequence sets and write transform sql commands
open(OUT,">$opt_p") || die "cannot open $opt_p";
print OUT "#\n# sql autogenerated by make_vega.pl\n#\n\n";

# delete orphan chromosomes, assemblies

my $chrid_string=join(',',(keys %chr_id));
print OUT "# remove unneeded assembly entries\n";
print OUT "delete frome assembly where type not in ($type_string);\n\n";
print OUT "# remove unneeded chrosome entries\n";
print OUT "delete from chromosome where chromosome_id not in ($chrid_string);\n\n";

# delete unwanted tables
# (should come from another meta table?)

# insert meta information
# (should come from another meta table?)



close(OUT);

print "Wrote files ok\n";

#$dbh->do(qq{});

$dbh->disconnect();
$dbh2->disconnect();

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
