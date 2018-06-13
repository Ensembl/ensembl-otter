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

assembly_tags.pl - transform assembly_tags into MiscFeatures

=head1 SYNOPSIS

assembly_tags.pl [options]

General options:
    --conffile, --conf=FILE             read parameters from FILE
                                        (default: conf/Conversion.ini)

    --dbname, db_name=NAME              use database NAME
    --host, --dbhost, --db_host=HOST    use database host HOST
    --port, --dbport, --db_port=PORT    use database port PORT
    --user, --dbuser, --db_user=USER    use database username USER
    --pass, --dbpass, --db_pass=PASS    use database passwort PASS
    --logfile, --log=FILE               log to FILE (default: *STDOUT)
    --logpath=PATH                      write logfile to PATH (default: .)
    --logappend, --log_append           append to logfile (default: truncate)
    -v, --verbose                       verbose logging (default: false)
    -i, --interactive=0|1               run script interactively (default: true)
    -n, --dry_run, --dry=0|1            don't write results to database
    -h, --help, -?                      print help (this message)

=head1 DESCRIPTION

This script tranforms assembly_tags into MiscFeatures with MiscSet
'AssemblyTag'. Tag type and info are stored as 'assembly_tag' Attributes.


=head1 AUTHOR

Patrick Meidl <pm2@sanger.ac.uk>

=head1 CONTACT

Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use FindBin qw($Bin);
use vars qw($SERVERROOT);
use Data::Dumper;

BEGIN {
    $SERVERROOT = "$Bin/../../../..";
    unshift(@INC, "$SERVERROOT/ensembl-otter/modules");
    unshift(@INC, "$SERVERROOT/ensembl/modules");
    unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Data::Dumper;
use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use Bio::EnsEMBL::MiscSet;
use Bio::EnsEMBL::MiscFeature;
use Bio::EnsEMBL::Attribute;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->allowed_params($support->get_common_params);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# get adaptors
my $dba = $support->get_database('ensembl');
my $sa = $dba->get_SliceAdaptor;
my $mfa = $dba->get_MiscFeatureAdaptor;
my $msa = $dba->get_MiscSetAdaptor;
my $dbh = $dba->dbc->db_handle;

# create a MiscSet
$support->log("Creating MiscSet 'AssemblyTag'...\n");
my $mset = Bio::EnsEMBL::MiscSet->new(
   -CODE => 'AssemblyTag',
   -NAME => 'Assembly tag',
   -DESCRIPTION => 'Assembly tag',
   -LONGEST_FEATURE => 1e10,
);
$msa->store($mset) unless $support->param('dry_run');
$support->log("Done.\n");

# read data from assembly_tag
$support->log("Reading assembly_tag and storing as MiscFeature...\n");
my $sth = $dbh->prepare("SELECT * FROM assembly_tag");
$sth->execute;
my %stats;
while (my $row = $sth->fetchrow_hashref) {
    # create a slice
    my $slice = $sa->fetch_by_seq_region_id($row->{'seq_region_id'});
    # hack to skip assembly_tag entries for non-existing contigs
    unless ($slice) {
        $stats{'skipped'}++;
        next;
    }
    
    # create MiscFeature and add MiscSet
    my $mfeat = Bio::EnsEMBL::MiscFeature->new(
            -START  => $row->{'seq_region_start'},
            -END    => $row->{'seq_region_end'},
            -STRAND => $row->{'seq_region_strand'},
            -SLICE  => $slice,
    );
    $mfeat->add_MiscSet($mset);

    # create Attribute and add to MiscFeature
    my $attrib = Bio::EnsEMBL::Attribute->new(
            -CODE   => 'assembly_tag',
            -NAME   => $row->{'tag_type'},
            -VALUE  => $row->{'tag_info'},
    );
    $mfeat->add_Attribute($attrib);

    # store MiscFeature
    $mfa->store($mfeat) unless $support->param('dry_run');

    # stats
    $stats{'ok'}++;
}
$support->log("Stored $stats{ok} assembly tags.\n", 1);
$support->log("Skipped $stats{skipped} assembly tags.\n", 1);
$support->log("Done.\n");

# drop now obsolete table assembly_tag
if ($support->user_proceed("Would you like to drop the assembly_tag table?")) {
    $support->log("Dropping table assembly_tag...\n");
    $dbh->do("DROP TABLE assembly_tag") unless $support->param('dry_run');
    $support->log("Done.\n");
}

# finish log
$support->finish_log;


