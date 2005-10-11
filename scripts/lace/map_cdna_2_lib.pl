#!/usr/local/bin/perl -w

# map_cdna_2_lib.pl

# ck1

# maps clones on plate to their clone_name and source libraries
# also outputs a composite cons file for plate19


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

# maps   eg: >XTropTFL19a01 FIN.0.1 (in plate19 cons file)
# to   this: >TEgg001a21 TEgg

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
	
	my $clonename = $lib.$src_plate.lc($src_well);

	print $dest_plate.lc($dest_well), $lib, $clonename, "\n"; die;
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
  }
	
  else {
	push(@{$cdna_fasta->{$lib}->{$cdna}}, $_);
  }
}

# this file is equivalent to all_x_trop_yyyy_mm_dd.fasta
# and needs to be loaded into database before blasting

my ($plate19);
my $fasta = "all_plate19_". $release . ".fasta";
open($plate19, ">>$fasta");

foreach my $lib ( keys %$cdna_fasta ){
  foreach my $cdna ( keys %{$cdna_fasta->{$lib}} ){
	print $plate19 @{$cdna_fasta->{$lib}->{$cdna}};
  }
}




