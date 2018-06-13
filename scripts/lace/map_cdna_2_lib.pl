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


use warnings;


# ck1
# Maps clones on plate to their clone_name and source libraries
#      and write out cons files for each library

# Run this script in the /nfs/disk100/humpub/est/tropicalis_cdna/tropicalis_load_x directory

use strict;

# currently, there are only 2 plate sources
my $cons_file_1 = $ARGV[0];
my $cons_file_2 = $ARGV[1];

my @plate_libs = qw(plate19.lib plate20.lib);
my $cdna_lib = {};

foreach my $lib ( @plate_libs ) {
  open(my $fh, '<', "/nfs/team71/analysis/ck1/FROG_PLATE_LIB/$lib") or die $!;

  while (<$fh> ) {
    chomp;

    # Format of platexx.lib
    # Lib     Pos     Src     Plate           Well
    # TEgg    30      A8      XTropTFL19      I11

    next if $_ =~ /^#/;

    my ( $lib, $pos, $src, $plate, $well ) = split(/\s+/, $_);

    if ( $well =~ /^([A-Z])(\d+)$/ ) {
      my $alpha = $1;
      my $num = sprintf("%02d", $2);
      $well = $alpha.$num;
    }

    if ( $src =~ /^([A-Z])(\d+)$/ ) {
      my $alpha = $1;
      my $num = sprintf("%02d", $2);
      $src = $alpha.$num;
    }

    $pos = sprintf("%03d", $pos);

    my $clonename = $lib.$pos.lc($src);
    print "$clonename\n" if length $clonename == 9;

    push(@{$cdna_lib->{$plate.lc($well)}}, $lib, $clonename );
  }
}

#foreach ( sort keys %$cdna_lib ){
#  print "$_ => @{$cdna_lib->{$_}}\n";
#}
#die;

my @cons_files = ($cons_file_1,$cons_file_2);
my $cdna_fasta = {};

foreach my $cons_file ( @cons_files ) {

  open(my $fh, '<', $cons_file) or die $!;

  my ($cdna, $lib, $plate);

  $plate = $cons_file;
  $plate =~ s/\..+//;  # eg, p19, p20

  while (<$fh> ) {

    # format of cons file FASTA header
    # >XTropTFL19p17 FIN.0.8
    # >XTrop20d06 FIN.0.7

    if ( $_ =~ />(XTropTFL19.+|XTrop20.+)\s.+/ ) {
      $cdna = $1;

      # the finishers has inconsisten format in cons file and
      # lib mapping layout

      $cdna =~ s/XTrop/XTropTFL/ if $cdna =~ /XTrop20/;

      $lib = $cdna_lib->{$cdna}->[0];
      my $clonename = $cdna_lib->{$cdna}->[1];

      my $header = ">$clonename $lib\n";
      push(@{$cdna_fasta->{$plate}->{$lib}->{$cdna}}, $header);
          print $header;
    }
    else {
      push(@{$cdna_fasta->{$plate}->{$lib}->{$cdna}}, $_);
    }
  }
}

foreach my $cons_file ( @cons_files ) {

  $cons_file =~ /(.+)\.(.+)/;
  my $plate    = $1;
  my $cons_ver = $2;
  my $cons_dir = $plate."Cons";

  my $fh;
  foreach my $lib ( keys %{$cdna_fasta->{$plate}} ) {

    # make dirs for libs found in cons file
    system("mkdir -p $cons_dir/$lib");

    open($fh, '>>', "$cons_dir/$lib/$cons_ver") or die $!;

    foreach my $cdna ( keys %{$cdna_fasta->{$plate}->{$lib}} ) {
      print $fh @{$cdna_fasta->{$plate}->{$lib}->{$cdna}}, "\n";
    }
  }
}



