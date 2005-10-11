#!/usr/local/bin/perl -w

### ck1
### maps clones on plate to their clone_name and source libraries
### map_cdna_2_lib.pl


use strict;
use Getopt::Long 'GetOptions';
use DBI;
use ck1_modules::MySQL_DB;

my $cons_file = $ARGV[0];
my $release   = $ARGV[1];
my $dbname    = $ARGV[2];

unless ( @ARGV == 3 ){
  print "\nCommand: map_cdna_2_lib.pl cons_file release_date dbname\n\n";
  exit;
}

my $db = new MySQL_DB;
my $dbh = $db->connect_db($dbname, "otterpipe2", 3303, "ottro", "");

my $cdna_lib = get_clone_mapping();

sub get_clone_mapping {

  my $sql = $dbh->prepare("SELECT * FROM clone_map");
  $sql->execute;

  my $cdna_lib = {};

  while ( my $href = $sql->fetchrow_hashref ){
	
	my $lib        = $href->{library};
	my $src_plate  = $href->{src_plate};
	my $src_well   = $href->{src_well};
	my $dest_plate = $href->{dest_plate};
	my $dest_well  = $href->{dest_well};

	if ( $dest_well =~ /^([A-Z])(\d+)$/ ){
	  my $alpha = $1;
	  my $num = sprintf("%02d", $2);
	  $dest_well = $alpha.$num;
	}

	if ( $src_well =~ /^([A-Z])(\d+)$/ ){
	  my $alpha = $1;
	  my $num = sprintf("%02d", $2);
	  $src_well = $alpha.$num;
	}
	
	$src_plate = sprintf("%03d", $src_plate);
	
	warn my $clonename = $lib.$src_plate.lc($src_well);

	push(@{$cdna_lib->{$dest_plate.lc($dest_well)}}, $lib, $clonename );
  }

  return $cdna_lib;
}

open(my $fh, "$cons_file") or die $!;

my $cdna_fasta = {};
my ( $cdna, $lib );

while (<$fh> ){

  #XTropTFL19p17 FIN.0.8

  if ( $_ =~ />(XTropTFL19.+)\s(.+)/ ){
	$cdna = $1;
 	$lib = $cdna_lib->{$cdna}->[0];
	my $clonename = $cdna_lib->{$cdna}->[1];

	my $header = ">$clonename $lib\n";
	push(@{$cdna_fasta->{$lib}->{$cdna}}, $header);
	print $header;
  }
	
  else {
	push(@{$cdna_fasta->{$lib}->{$cdna}}, $_);
  }
}

my ($plate19);
my $fasta = "all_plate19_". $release . ".fasta";
open($plate19, ">>$fasta");

foreach my $lib ( keys %$cdna_fasta ){
  foreach my $cdna ( keys %{$cdna_fasta->{$lib}} ){
	print $plate19 @{$cdna_fasta->{$lib}->{$cdna}};
  }
}




