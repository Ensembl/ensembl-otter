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


=head1 NAME

QC_chromosome_version.pl

=head1 SYNOPSIS

QC_chromosome_version.pl

=head1 DESCRIPTION

This script is part of a set of quality control scripts, it checks the chromosome versions in the pipeline databases 
and print a warning or change its version if more than one version of a chromosome is present. 
The old chromosomes in the pipeline datbases should all be OtterArchive chromosome version to 
prevent problem when fetching features on chromosome slice.

here is an example commandline

./QC_chromosome_version.pl


=head1 OPTIONS

    -host (default:otterpipe1,otterpipe2)   host name for the pipeline databases
    -dbname (optional) pipeline database name
    -user (check the ~/.netrc file)  what username to connect as
    -pass (check the ~/.netrc file)  what password to use
    -port (check the ~/.netrc file)  what port to use

    -change	make the detected old chromosome OtterArchive (to use with extreme caution :-)
    -help|h	displays this documentation with PERLDOC

=head1 CONTACT

Mustapha Larbaoui B<email> ml6@sanger.ac.uk

=cut

use strict;
use warnings;

use Getopt::Long;
use DBI;
use Net::Netrc;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);

my @dbnames;
my $hosts = ['otterpipe1','otterpipe2'];
my $user;
my $port;
my $pass;
my $change;
my $help;
my $usage = sub { exec( 'perldoc', $0 ); };

GetOptions(
			'host=s@'   => \$hosts,
			'port=n'   => \$port,
			'dbname=s' => \@dbnames,
			'user=s'   => \$user,
			'pass=s'   => \$pass,
			'change!'  => \$change,
			'h|help!'  => $usage,
) or $usage->();

@$hosts   = map( split( /,/, $_ ), @$hosts );
@dbnames = map( split( /,/, $_ ), @dbnames );

my $sql = qq/
    SELECT s.seq_region_id
      , a1.value AS chromosome
      , s.name AS seq_set
    FROM (attrib_type t1
          , coord_system c
          , seq_region s)
    LEFT JOIN seq_region_attrib a1
      ON (a1.seq_region_id = s.seq_region_id
          AND t1.attrib_type_id = a1.attrib_type_id)
    WHERE c.coord_system_id = s.coord_system_id
      AND t1.code = 'chr'
      AND c.name = 'chromosome'
      AND c.version = 'Otter'
      AND s.name LIKE 'chr%'
    ORDER BY chromosome
      , s.seq_region_id DESC
/;

foreach my $host (@$hosts) {
	my @db;
	if ( !@dbnames ) {
		# get the list of pipeline here
		my $sth = &get_sth($host,undef,"SHOW DATABASES LIKE 'pipe_%'");
		$sth->execute();
		while(my ($pipe) = $sth->fetchrow_array){
			push @db, $pipe;
		}
	} else {
		@db = @dbnames;
	}
	foreach(@db){
		next if /pipe_cow/;
		print STDOUT "QC_chr_version: Check $host:$_\n";
		&process_database($host,$_);
	}
}

sub process_database {
	my ($host,$db_name) = @_;
	my $hash;
	my $sth = &get_sth($host,$db_name,$sql);
	$sth->execute();
	while(my ($srid,$chr,$sr_name) = $sth->fetchrow_array){
		next unless $sr_name =~ /chr(\d+|X|Y|U|H)(-|_)(\d+|NCBIM37)/;
		if($hash->{$chr}) {
			# do something if more than one version
			print STDOUT "QC_chr_version: ${srid}|${chr}|${sr_name} should be OtterArchive\n";
			&change_version($host,$db_name,$srid) if $change;
		} else {
			$hash->{$chr} = [$srid,$sr_name];			
		}		
	}
}

sub change_version {
	my ($host,$db_name,$srid) = @_;
	print STDOUT "QC_chr_version: $srid changed to OtterArchive\n";
	my $sql = qq{
		UPDATE seq_region s, coord_system cs
		SET s.coord_system_id = cs.coord_system_id
		WHERE cs.version = 'OtterArchive'
		AND s.seq_region_id = $srid
	};	
	my $sth = &get_sth($host,$db_name,$sql);
	$sth->execute;
}

my %dbi_hash;
sub get_sth {
	my ($host,$db_name,$sql) = @_;
	$db_name ||= 'no_db';
	if(!$dbi_hash{$host}->{$db_name}){
		my $ref = Net::Netrc->lookup($host);
		thow("No entry found in ~/.netrc for host $host") unless $ref;
		$user = $ref->login if $ref->login;
		$pass = $ref->password if $ref->password;
		$port = $ref->account if $ref->account;
	
		# Creating the DB connection
		my $database = $db_name ne 'no_db' ? "database=$db_name":"";
		my $dsn = "DBI:mysql:$database;host=$host;port=$port";
		my $dbh = DBI->connect( $dsn, $user, $pass, { 'RaiseError' => 1 } );
		$dbi_hash{$host}->{$db_name} = $dbh;		
	}

	my $sth = $dbi_hash{$host}->{$db_name}->prepare($sql);	
	
	return $sth;
}



