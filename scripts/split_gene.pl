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


# script to carry out most of changes required (by SQL) to create
# a new gene and move some of the transcripts to it - see help for
# more details.

use strict;
use Getopt::Long;
use DBI;
use Sys::Hostname;

# hard wired
my $driver="mysql";
my $port=3352;
my $password;
my $host='ecs4';
my $user='ensadmin';
my $db='human_vega5c_copy';
my $help;
my $phelp;
my $opt_v;
my $opt_u;
my $opt_g;
my $opt_t;
my $opt_s;
my $opt_n;
my $opt_o='split_gene.sql';

$Getopt::Long::ignorecase=0;

GetOptions(
	   'port:s', \$port,
	   'pass:s', \$password,
	   'host:s', \$host,
	   'user:s', \$user,
	   'db:s', \$db,

	   'help', \$phelp,
	   'h', \$help,
	   'v', \$opt_v,
	   'g:s', \$opt_g,
	   't:s', \$opt_t,
	   's:s', \$opt_s,
	   'n:s', \$opt_n,
	   'o:s', \$opt_o,
	   );

# help
if($phelp || !$opt_g || !$opt_t || !$opt_n || !$opt_s){
    exec('perldoc', $0);
    exit 0;
}
if($help){
    print<<ENDOFTEXT;
split_gene.pl
  -host           char      host of mysql instance ($host)
  -db             char      database ($db)
  -port           num       port ($port)
  -user           char      user ($user)
  -pass           char      passwd

  -h                        this help
  -help                     perldoc help
  -v                        verbose
  -g              num       gene_id of gene to split
  -t              num[,num] transcript_id(s) of transcripts to be moved to new gene
  -n              char      name of new gene
  -o              file      file of all sql (for reference)
  -s              char      stable id of new gene

Need to propose new stable_id for gene.
Use 'select max(gene_stable_id) from gene_stable_id_pool' and add 1
ENDOFTEXT
    exit 0;
}

# connect
my $dbh;
if(my $err=&_db_connect(\$dbh,$host,$db,$user,$password)){
    print "failed to connect $err\n";
    exit 0;
}

my %trans;
%trans=map{$_,1}split(/,/,$opt_t);

# check gid and tid are consistent
my $sth=$dbh->prepare("select transcript_id from transcript where gene_id=$opt_g");
$sth->execute;
my $nother_trans=0;
my $ntrans=0;
while (my @row = $sth->fetchrow_array()){
    my $tid=$row[0];
    if($trans{$tid}){
	$trans{$tid}=2;
	$ntrans++;
    }else{
	print "found other transcript $tid\n";
	$nother_trans++;
    }
}
my $err=0;
foreach my $tid (keys %trans){
    if($trans{$tid}==1){
	print "FATAL transcript id $tid not found\n";
	$err=1;
    }
}
exit 0 if $err;
print "$ntrans found, $nother_trans found\n";

exit 0 unless $opt_s;

# gene_stable_id_pool
open(OUT,">$opt_o") || die "cannot open $opt_o";

my $query="insert into gene_stable_id_pool values(null,\'$opt_s\',now())";
print OUT "$query\n";
my $sth=$dbh->prepare($query);
$sth->execute;

# (get new gene_stable_id)
$query="select gene_stable_id from gene_stable_id_pool where gene_pool_id=last_insert_id()";
$sth=$dbh->prepare($query);
$sth->execute;
my $gsid;
while (my @row = $sth->fetchrow_array()){
    $gsid=$row[0];
}
if(!$gsid){
    print "failed to get new gene_stable_id\n";
    exit 0;
}

$query="insert into gene values(null,\'Novel_CDS\',19,$ntrans,0)";
print OUT "$query\n";
$sth=$dbh->prepare($query);
$sth->execute;

# (get new gene_id)
$query="select last_insert_id()";
$sth=$dbh->prepare($query);
$sth->execute;
my $gid;
while (my @row = $sth->fetchrow_array()){
    $gid=$row[0];
}
if(!$gid){
    print "failed to get new gene_id\n";
    exit 0;
}
# gene_stable_id
$query="insert into gene_stable_id values($gid,\'$gsid\',1,now(),now())";
print OUT "$query\n";
$sth=$dbh->prepare($query);
$sth->execute;

$query="update gene set transcript_count=$nother_trans where gene_id=$opt_g";
print OUT "$query\n";
$sth=$dbh->prepare($query);
$sth->execute;

print "new gene is $gid, $gsid; $ntrans moved to this gene from $opt_g\n";

# fix transcript ownership
foreach my $tid (keys %trans){
    $query="update transcript set gene_id=$gid where transcript_id=$tid";
    print OUT "$query\n";
    $sth=$dbh->prepare($query);
    $sth->execute;
}

# gene_description (leave blank)

# get current gene_info entry:
my $sth=$dbh->prepare("select gi.author_id from gene_info gi, current_gene_info cgi, gene_stable_id gsi where gi.gene_info_id=cgi.gene_info_id and cgi.gene_stable_id=gsi.stable_id and gsi.gene_id=$opt_g");
$sth->execute;
my $authorid;
while (my @row = $sth->fetchrow_array()){
    $authorid=$row[0];
}
if(!$authorid){
    print "failed to get authorid from gene_info\n";
    exit 0;
}

# create gene_info entry:
$query="insert into gene_info values(null,\'$gsid\',$authorid,\'false\',now())";
print OUT "$query\n";
$sth=$dbh->prepare($query);
$sth->execute;
my $sth=$dbh->prepare("select last_insert_id()");
$sth->execute;
my $giid;
while (my @row = $sth->fetchrow_array()){
    $giid=$row[0];
}
if(!$giid){
    print "failed to get new gene_info_id\n";
    exit 0;
}

# create current_gene_info entry:
$query="insert into current_gene_info values($giid,\'$gsid\')";
print OUT "$query\n";
$sth=$dbh->prepare($query);
$sth->execute;


# gene_name (new name)
$query="insert into gene_name values(null,\'$opt_n\',$giid)";
print OUT "$query\n";
$sth=$dbh->prepare($query);
$sth->execute;

# gene_remark (nothing)

$dbh->disconnect();

exit 0;

# connect to db with error handling
sub _db_connect{
    my($rdbh,$host,$database,$user,$password)=@_;
    my $dsn = "DBI:$driver:database=$database;host=$host;port=$port";

    # try to connect to database
    eval{
	$$rdbh = DBI->connect($dsn, $user, $password,
			    { RaiseError => 1, PrintError => 0 });
    };
    if($@){
	print "$database not on $host\n$@\n" if $opt_v;
	return -2;
    }
}

__END__


=pod

=head1 split_gene.pl

=head1 DESCRIPTION

To fix otter database (directly by manipulating the SQL, as API does
not support this) to split a gene that contains multiple transcripts
that have incorrectly been grouped together.  Involves creating a new
stableID, updating gene, gene_info, transcript tables.  Use is not
straightward and requires mysql access to database to carry out a few
queries to collect a number of parameters required to run script.
Script writes SQL that was used to change database into a file
split_gene.sql, for reference.

=head1 EXAMPLES

Suppose you know that OTTHUMG00000099999 had transcripts that should
not be together:

1) find gene_id

    select * from gene_stable_id where stable_id = 'OTTHUMG00000099999';

88888

2) find transcript_ids and identify ones that should be separated and
made part of new gene.

    select et.*,e.contig_id,a.type,a.chr_start,a.chromosome_id,c.name \
    from contig c, transcript t, exon_transcript et, exon e, assembly a \
    where t.transcript_id=et.transcript_id and et.exon_id=e.exon_id and \
    a.contig_id=e.contig_id and c.contig_id=e.contig_id and t.gene_id=88888;

    select tr.* from transcript_remark tr, current_transcript_info cti, \
    transcript_stable_id tsi, transcript t where t.transcript_id=tsi.transcript_id \
    and tsi.stable_id=cti.transcript_stable_id and \
    cti.transcript_info_id=tr.transcript_info_id and t.gene_id=88888;

Identify 55555,55556 as 2 transcripts to move:

3) identify next unused stable id:

    select max(gene_stable_id) from gene_stable_id_pool;

OTTHUMG00000100000+1 => OTTHUMG00000100001

4) run script, with value for gene_name table
    
    split_gene.pl -g 88888 -t 55555,55556 -db otter_species -n NAME \
    -s OTTHUMG00000100001 -port 3306 -host MACHINE
    

=head1 FLAGS

=over 4

=item -h

Displays short help

=item -help

Displays this help message

=back

=head1 VERSION HISTORY

=over 4

=item 15-MAR-2003

B<th> released first version

=back

=head1 BUGS

=head1 AUTHOR

B<Tim Hubbard> Email th@sanger.ac.uk

=cut
