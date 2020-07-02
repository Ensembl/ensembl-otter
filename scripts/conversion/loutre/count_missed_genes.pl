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


=head1 NAME

count_missed_genes.pl - see how many genes got missed when making loutre since they were in progress

=head1 SYNOPSIS

    ./count_missed_genes.pl
    --conffile, --conf=FILE             read parameters from FILE
                                        (default: conf/Conversion.ini)
    --logfile, --log=FILE               log to FILE (default: *STDOUT)
    --logpath=PATH                      write logfile to PATH (default: .)
    --logappend, --log_append           append to logfile (default: truncate)
    -h, --help, -?                      print help (this message)

Specific options:

details of previous database to compare against:
    --lastdbname=STRING
    --lasthost=S
    --lastport=S
    --lastuser=S
    --lastpass=S

    --log_input=FILE                    log file from loutre_dumping


=head1 DESCRIPTION

Grep through a log file for in_progess genes that have not been transferred - compare these against the
previous database to see which are new and which will now be missing


=head1 AUTHOR

Steve Trevanion <st3@sanger.ac.uk>

=head1 CONTACT

Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

=cut

use strict;
use FindBin qw($Bin);
use vars qw( $SERVERROOT );
use Data::Dumper;

BEGIN {
  $SERVERROOT = "$Bin/../../../..";
  unshift @INC,"$SERVERROOT/ensembl/modules";
  unshift @INC,"$SERVERROOT/bioperl-live";
  unshift @INC,"$SERVERROOT/modules";
  unshift @INC,"$SERVERROOT/ensembl-compara/modules";
  unshift @INC,"$SERVERROOT/ensembl-draw/modules";
  unshift @INC,"$SERVERROOT/ensembl-external/modules";
  unshift @INC,"$SERVERROOT/conf";
}

use Bio::EnsEMBL::Utils::ConversionSupport;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
  'lastdbname=s',
  'lasthost=s',
  'lastport=s',
  'lastuser=s',
  'lastpass=s',
  'log_input=s',
);
$support->allowed_params(
  $support->get_common_params,
  'lastdbname',
  'lasthost',
  'lastport',
  'lastuser',
  'lastpass',
  'log_input',
);

#guess what log file to read unless it's been specified
unless ($support->param('log_input')) {
  my $log_file = 'dump_loutre_001.log';
  if ($support->param('nolog')) {
    my $dbname = $support->param('dbname');
    $dbname =~ s/^vega_//;
    $support->param('log_input',($support->param('log_base_path').'/'.$dbname.'/'.$log_file));
  }
  else {
    $support->param('log_input',($support->param('logpath').$log_file));
  }
}

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

$support->init_log;

#get database adaptors
my $dbh = $support->get_database('ensembl','last');
my $ga  = $dbh->get_GeneAdaptor;

my $in  = $support->filehandle('<', $support->param('log_input'));
my (%previous,%new,$seq_regions);

while (<$in>) {
  chomp;
  if ($_ =~ /annotation in progress/) {
    (my $gsi) = $_ =~ /(OTT\w{4}\d{11})/;
    (my $author) = $_ =~ /\((\w+)\)$/;
    if (my $g = $ga->fetch_by_stable_id($gsi)) {
      $previous{$gsi}++;
      my $gname = $g->get_all_Attributes('name')->[0]->value;
      push @{$seq_regions->{$g->seq_region_name}}, "$gsi ($gname) ($author)";
    }
    else {
      $new{$gsi}++;
    }
  }
}

if (my $c = keys %new) {
  $support->log("\nThere are $c new loutre genes that haven't been dumped:\n");
  foreach my $k (keys %new) {
    $support->log("$k\n");
  }
}

if (my $c = keys %previous) {
  $support->log("\nThere are $c existing Vega genes that haven't been dumped from loutre this time:\n");
  foreach my $k (keys %previous) {
    $support->log("$k\n");
  }
  $support->log("If you need to dump them use this list:\n" . join(',',keys %previous) . "\n");
  $support->log("\nThese are on the following seq_regions:\n");
  $support->log(Dumper($seq_regions));
}

$support->log("Done.\n");

# finish log
$support->finish_log;


