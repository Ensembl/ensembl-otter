#!/usr/local/bin/perl --    # -*-Perl-*-
#
# Copyright (c) 1997 Tim Hubbard (th@sanger.ac.uk)
# Sanger Centre, Wellcome Trust Genome Campus, Cambs, UK
# All rights reserved.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation
#
# $Header: /tmp/ENSCOPY-ENSEMBL-OTTER/scripts/conversion/Attic/change_otterid_namespace.pl,v 1.5 2004-01-27 12:27:55 th Exp $
#
# Function:
# T: 
# D: 
#

use strict;
use Getopt::Long;
use DBI;
use Sys::Hostname;

# hard wired
my $driver="mysql";

# default
my $port=3306;
my $password;
my $host='ecs2a';
my $user='ensadmin';
my $dbname='otter_chr20_test_copy';
my $help;
my $phelp;
my $opt_v;
my $opt_c;
my $opt_z;
my $opt_t;
my $dbtype='otter';

$|=1;

my $opt_o='patch.sql';
my $opt_O='HUM';
my $opt_p='20';
my $opt_f;

$Getopt::Long::ignorecase=0;

GetOptions(
	   'port:n', \$port,
	   'pass:s', \$password,
	   'host:s', \$host,
	   'user:s', \$user,
	   'dbname:s', \$dbname,

	   'O:s', \$opt_O,
	   'o:s', \$opt_o,
	   'p:s', \$opt_p,
	   'help', \$phelp,
	   'dbtype:s', \$dbtype,

	   'h', \$help,
	   'v', \$opt_v,
	   'c', \$opt_c,
	   'z', \$opt_z,
	   'f:s', \$opt_f,
	   't:n', \$opt_t,
	   );

# help
if($phelp){
    exec('perldoc', $0);
    exit 0;
}
if($help){
    print<<ENDOFTEXT;
change_otterid_namespace.pl
  -host           txt     host of mysql instance [$host]
  -pass           txt     password
  -dbname         txt     name of database [$dbname]
  -port           num     port number of mysqld instance [$port]
  -user           txt     user name [$user]
  -o              file    output file name [$opt_o]
  -O              txt     species prefix [$opt_O]
  -p              txt     namespace prefix [$opt_p]
  -dbtype         txt     otter/ensembl [$dbtype]

  -h                      this help
  -help                   perldoc help
  -v                      verbose
  -c                      order by row count
  -z                      omit tables with zero row count
  -f              txt     filter on chromosome (can be same as $opt_p)
  -t              num     test (use 'limit X')
ENDOFTEXT
    exit 0;
}

# connect
my $dbh;
if(my $err=&_db_connect(\$dbh,$host,$dbname,$user,$password)){
    print "failed to connect $err\n";
    exit 0;
}

my $test;
if($opt_t){$test="limit $opt_t";}

# loop over list of tables requiring edits, extracting data, modifying and writing patch

my %tables;

my $sqlf1=", exon e, assembly a, chromosome c where exon_stable_id.exon_id = e.exon_id and e.contig_id = a.contig_id and a.chromosome_id = c.chromosome_id and c.name = ";
$tables{'exon_stable_id'}=['exon_id','stable_id','E',$sqlf1];

my $sqlf3=", transcript t, exon_transcript et, exon e, assembly a, chromosome c where gene_stable_id.gene_id = t.gene_id and t.transcript_id = et.transcript_id and et.exon_id = e.exon_id and e.contig_id = a.contig_id and a.chromosome_id = c.chromosome_id and c.name = ";
$tables{'gene_stable_id'}=['gene_id','stable_id','G',$sqlf3];

my $sqlf2=", exon_transcript et, exon e, assembly a, chromosome c where transcript_stable_id.transcript_id = et.transcript_id and et.exon_id = e.exon_id and e.contig_id = a.contig_id and a.chromosome_id = c.chromosome_id and c.name = ";
$tables{'transcript_stable_id'}=['transcript_id','stable_id','T',$sqlf2];

my $sqlf4=", transcript t, exon_transcript et, exon e, assembly a, chromosome c where translation_stable_id.translation_id = t.translation_id and t.transcript_id = et.transcript_id and et.exon_id = e.exon_id and e.contig_id = a.contig_id and a.chromosome_id = c.chromosome_id and c.name = ";
$tables{'translation_stable_id'}=['translation_id','stable_id','P'];

$tables{'xref'}=['xref_id','dbprimary_acc','EGTP'];

if($dbtype eq 'otter'){

  my $sqlf5=", gene_stable_id g, transcript t, exon_transcript et, exon e, assembly a, chromosome c where current_gene_info.gene_stable_id = g.stable_id and g.gene_id and t.gene_id and t.transcript_id = et.transcript_id and et.exon_id = e.exon_id and e.contig_id = a.contig_id and a.chromosome_id = c.chromosome_id and c.name = ";
  $tables{'current_gene_info'}=['gene_info_id','gene_stable_id','G'];

  $tables{'current_transcript_info'}=['transcript_info_id','transcript_stable_id','T'];
  # exon_stable_id
  $tables{'exon_stable_id_pool'}=['exon_pool_id','exon_stable_id','E'];

  my $sqlf6=", gene_stable_id g, transcript t, exon_transcript et, exon e, assembly a, chromosome c where gene_info.gene_stable_id = g.stable_id and g.gene_id = t.gene_id and t.transcript_id = et.transcript_id and et.exon_id = e.exon_id and e.contig_id = a.contig_id and a.chromosome_id = c.chromosome_id and c.name = ";
  $tables{'gene_info'}=['gene_info_id','gene_stable_id','G'];

  # gene_stable_id
  my $sqlf7=", gene_stable_id g, transcript t, exon_transcript et, exon e, assembly a, chromosome c where gene_stable_id_pool.gene_stable_id = g.stable_id and g.gene_id = t.gene_id and t.transcript_id = et.transcript_id and et.exon_id = e.exon_id and e.contig_id = a.contig_id and a.chromosome_id = c.chromosome_id and c.name = ";
  $tables{'gene_stable_id_pool'}=['gene_pool_id','gene_stable_id','G'];

  $tables{'transcript_info'}=['transcript_info_id','transcript_stable_id','T'];
  # transcript_stable_id
  $tables{'transcript_stable_id_pool'}=['transcript_pool_id','transcript_stable_id','T'];
  # translation_stable_id
  my $sqlf8=", translation_stable_id tsi, transcript t, exon_transcript et, exon e, assembly a, chromosome c where translation_stable_id_pool.translation_stable_id = tsi.stable_id and tsi.translation_id and t.translation_id and t.transcript_id = et.transcript_id and et.exon_id = e.exon_id and e.contig_id = a.contig_id and a.chromosome_id = c.chromosome_id and c.name = ";
  $tables{'translation_stable_id_pool'}=['translation_pool_id','translation_stable_id','P'];
  # xref
}

open(OUT,">$opt_o") || die "cannot open $opt_o";

foreach my $table (keys %tables){

  my $n=0;
  my $n2=0;
  my $n3=0;
  my $ns=0;
  my($key,$val,$type,$sqlfilter)=@{$tables{$table}};
  my $sql;
  if($opt_f){
    if($sqlfilter){
      $sql="$sqlfilter \'$opt_f\'";
    }else{
      print "no filter for $table - skip\n";
      next;
    }
  }
  my $sql2="select distinct $table.$key,$table.$val from $table $sql $test";
  #print "EXE $sql2\n";
  my $sth = $dbh->prepare($sql2);
  $sth->execute;
  while (my($key1,$val1)=$sth->fetchrow_array()){
    my $match='OTT'.$opt_O."[$type]".'000';
    my $match2="OTT[$type]".'000000';
    my $match3="OTT[$type]".'000';
    if($val1=~/^($match)00(\d{6})$/){
      # ready to change
      print OUT "update $table set $val=\'$1$opt_p$2\' where $key=$key1;\n";
      $n++;
    }elsif($val1=~/^($match2)00(\d{6})$/){
      # ready to change 
      $match='OTT'.$opt_O.$type.'000';
      print OUT "update $table set $val=\'$match$opt_p$2\' where $key=$key1;\n";
      $n2++;
    }elsif($val1=~/^($match3)00(\d{6})$/){
      # ready to change 
      $match='OTT'.$opt_O.$type.'000';
      print OUT "update $table set $val=\'$match$opt_p$2\' where $key=$key1;\n";
      $n2++;
    }elsif($val1=~/^OTT000000(\d{6})$/){
      # ready to change completely
      if(length($type)>1){
	print "cannot change when type is ambigous: $table: $key=\'$key1\'; $val=\'$val1\' $type\n";
	exit 0;
      }
      $match='OTT'.$opt_O.$type.'000';
      print OUT "update $table set $val=\'$match$opt_p$1\' where $key=$key1;\n";
      $n3++;
    }elsif($val1=~/^($match)$opt_p(\d{6})$/){
      # matches ok already
      $ns++;
    }else{
      print "$table: $key=\'$key1\'; $val=\'$val1\' could not parse [$match] [$match2]\n";
      exit 0;
    }
  }
  $sth->finish;
  print "$n;$n2;$n3 records modified for TABLE $table, $ns already ok\n";

}
close(OUT);

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

=head1 NAME - name



=head1 DESCRIPTION



=head1 SYNOPSIS



=head1 EXAMPLES



=head1 FLAGS

=over 4

=item -h

Displays short help

=item -H

Displays this help message

=back

=head1 VERSION HISTORY

=over 4

=item XX-XXX-1999

B<th> added

=back

=head1 BUGS

=head1 AUTHOR

B<Tim Hubbard> Email th@sanger.ac.uk

=cut
