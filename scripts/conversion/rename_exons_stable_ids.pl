#!/usr/local/bin/perl -w

=head1 NAME

rename_exon_stable_ids.pl 

=head1 SYNOPSIS

rename_exon_stable_ids.pl [options]

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

Gives new stable IDs to duplicated exons

Requires the exon_stable_id_pool table populated with the highest ranking
integer for existing exon_stable_ids.

=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

=head1 AUTHOR

Steve Trevanion <st3@sanger.ac.uk>

=head1 CONTACT

Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

BEWARE the bug (OTTE not OTTHUME)

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use FindBin qw($Bin);
use vars qw($SERVERROOT);

BEGIN {
    $SERVERROOT = "$Bin/../../..";
    unshift(@INC, "$SERVERROOT/ensembl/modules");
    unshift(@INC, "$SERVERROOT/ensembl-otter/modules");
    unshift(@INC, "$SERVERROOT/bioperl-live");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use Bio::Vega::DBSQL::DBAdaptor;
use Bio::Vega::DBSQL::StableIdAdaptor;
use Data::Dumper;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);

$support->allowed_params(
    $support->get_common_params,
);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors
my $dba = $support->get_database('loutre');
my $dbh = $dba->dbc->db_handle;
my $stida = $dba->get_StableIdAdaptor();

#get duplicate ids
my $sth = $dbh->prepare(qq(
        SELECT list.stable_id,
                esi2.exon_id, sr2.name, e2.seq_region_start, e2.seq_region_end
        FROM        (SELECT esi.stable_id
                     FROM exon e, exon_stable_id esi
                     WHERE e.exon_id=esi.exon_id
                     GROUP BY esi.stable_id, esi.version
                     HAVING sum(is_current)>1) list,
                 exon_stable_id esi1,
                 exon e1,
                 seq_region sr1,
                 exon_stable_id esi2,
                 exon e2,
                 seq_region sr2
         WHERE esi1.stable_id=list.stable_id
         AND esi1.version=1
         AND e1.exon_id=esi1.exon_id
         AND sr1.seq_region_id=e1.seq_region_id
         AND esi2.stable_id=list.stable_id
         AND esi2.version=1
         AND e2.exon_id=esi2.exon_id
         AND sr2.seq_region_id=e2.seq_region_id
         AND e1.exon_id<e2.exon_id
    ));

$sth->execute();
my %id_to_coords;
while( my ($stable_id, $exon_id, $ssname, $start, $end) = $sth->fetchrow() ) {
	$id_to_coords{$exon_id} = [ $stable_id, $ssname, $start, $end ];
}

foreach my $obj_id (keys %id_to_coords) {
    my ($old_stable_id, $ssname, $start, $end) = @{ $id_to_coords{$obj_id} };
	my $new_stable_id = $stida->fetch_new_exon_stable_id();
	if (! $support->param('dry_run')) {
		set_stable_id('exon', $obj_id, $new_stable_id);
	}
	$support->log("$old_stable_id ($obj_id): $ssname $start-$end ->  $new_stable_id\n");
}


sub set_stable_id {
    my ($type, $obj_id, $new_stid) = @_;

    my $sql = qq{
        UPDATE ${type}_stable_id SET stable_id='$new_stid' WHERE ${type}_id = $obj_id
    };
    my $sth = $dba->dbc()->prepare($sql);
	$sth->execute();
}
