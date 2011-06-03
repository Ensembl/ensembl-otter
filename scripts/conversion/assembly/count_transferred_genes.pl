#!/usr/bin/env perl

=head1 NAME

count_transferred_genes.pl - compare gene / transcripts numbers in two databases

=head1 SYNOPSIS

    ./ount_transferred_genes.pl
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

    --ftp_mirror=DIR                    directory to store logfile in
    --ftp_species=SPECIES               species (reqd for location of dump file)


=head1 DESCRIPTION

This script generates compares numbers of genes and transcripts between two ensembl-vega databases

Simple sql is used so the databases don't have to be on the same schema version.

=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

=head1 AUTHOR

Steve Trevanion <st3@sanger.ac.uk>

=head1 CONTACT

Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

=cut

use strict;
use FindBin qw($Bin);
use vars qw( $SERVERROOT );

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
  'evegahost=s',
  'evegaport=s',
  'evegauser=s',
  'evegapass=s',
  'evegadbname=s',
  'lastdbname=s',
);
$support->allowed_params(
  $support->get_common_params,
  'evegahost',
  'evegaport',
  'evegauser',
  'evegapass',
  'evegadbname',
  'lastdbname',
);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

my $this_db = $support->param('evegadbname');
my $last_db = $support->param('lastdbname');

exit unless ($support->user_proceed("Proceed with comparing $this_db against $last_db ?"));
	
$support->init_log;

#get database adaptors
my $new_dbh = $support->get_database('ensembl','evega')->dbc->db_handle;
my $old_dbh = $support->get_database('ensembl','last')->dbc->db_handle;

my $cond = ($support->param('evegadbname') =~ /homo/) ? "and a.logic_name = 'otter'" : '';
my ($old,$new);

foreach my $t (qw(gene transcript)) {
  $new->{$t}       = { map { @$_ } @{$new_dbh->selectall_arrayref( "select sr.name, count(*) from analysis a, $t t, seq_region sr where a.analysis_id = t.analysis_id and t.seq_region_id = sr.seq_region_id $cond group by sr.name" )} };
}

foreach my $t (qw(gene transcript)) {
  $old->{$t}       = { map { @$_ } @{$old_dbh->selectall_arrayref( "select sr.name, count(*) from  analysis a, $t t, seq_region sr where a.analysis_id = t.analysis_id and t.seq_region_id = sr.seq_region_id $cond group by sr.name" )} };
}

my $fmt = "%-20s%-20s%-20s%-25s%-25s\n";
$support->log("\nGene numbers:\n");
$support->log(sprintf($fmt, 'Chromosome','New gene count','Old gene count','Difference'));
foreach my $sr (sort keys %{$new->{'gene'}} ) {
  $support->log(sprintf($fmt,$sr,$new->{'gene'}{$sr},$old->{'gene'}{$sr},$new->{'gene'}{$sr}-$old->{'gene'}{$sr}));
}
$support->log("\nTranscript numbers:\n");
$support->log(sprintf($fmt, 'Chromosome','New trans count','Old trans count','Difference'));
foreach my $sr (sort keys %{$new->{'transcript'}} ) {
  $support->log(sprintf($fmt,$sr,$new->{'transcript'}{$sr},$old->{'transcript'}{$sr},$new->{'transcript'}{$sr}-$old->{'transcript'}{$sr}));
}

#warn Dumper($new);


$support->log("Done.\n");

# finish log
$support->finish_log;


