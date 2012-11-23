#!/usr/local/bin/perl

=head1 NAME

fix_gene_names.pl

=head1 SYNOPSIS

    ./fix_gene_names.pl
        --conffile, --conf=FILE        read parameters from FILE
                                       (default: conf/Conversion.ini)

    -loutredbname=NAME                 loutre database NAME
    -loutrehost=HOST                   loutre database host HOST
    -loutreport=PORT                   loutre database port PORT
    -loutreuser=USER                   loutre database username USER
    -loutrepass=PASS                   loutre database passwort PASS
    -logfile, --log=FILE               log to FILE (default: *STDOUT)
    -logpath=PATH                      write logfile to PATH (default: .)
    -logappend, --log_append           append to logfile (default: append)
    -v, --verbose                      verbose logging (default: false)
    -h, --help, -?                     print help (this message)
    -gene_file=FILE                    location of file containing stable IDs and new names

=head1 DESCRIPTION

Update display_xrefs and description, add a synonym for the old name.
Requires a specific input file format, and really isspecific for HGNC

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
}

use Bio::EnsEMBL::Utils::ConversionSupport;
use Pod::Usage;
use Data::Dumper;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

$support->parse_common_options(@_);
$support->parse_extra_options(
  'gene_file=s',
);
$support->allowed_params(
  $support->get_common_params,
  'gene_file',
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
my $dba = $support->get_database('ensembl');
my $ga  = $dba->get_GeneAdaptor();
my $ea  = $dba->get_DBEntryAdaptor();
my $dbh = $dba->dbc->db_handle;

# statement handles for display_xref_id update
my $sth_xref = $dba->dbc->prepare(qq(UPDATE xref SET display_label = ? WHERE xref_id = ?));
my $sth_desc = $dba->dbc->prepare(qq(UPDATE gene SET description = ? WHERE stable_id = ?));
my $sth_ga   = $dba->dbc->prepare(qq(UPDATE gene_attrib SET value = ? WHERE attrib_type_id = 4 and value = ? and gene_id = ?));
#add synonym for old name
my $sth_syn = $dba->dbc->prepare(qq(
           INSERT into gene_attrib
           VALUES (?,
                   (SELECT attrib_type_id FROM attrib_type WHERE code = 'synonym'),
                   ?)
           ));

#get new names from file and update each gene
$support->log("Retrieving details of genes from datafile...\n");
my $infile = $support->filehandle('<', $support->param('gene_file'));
my $c;
while (my $line = <$infile>) {

  next if ($line =~ /^#/);

  if ( my ( $gsi,$biotype,$sr,$old_name,$new_name,$desc ) = split '\t', $line) {
    $c++;
    chomp $desc;
    next if $gsi eq 'STABLE_ID';
    my $gene = $ga->fetch_by_stable_id($gsi);
    my $g_dbID = $gene->dbID;
    next unless $gene;

    my $current_dispxref = $gene->display_xref;
    my $current_name   = $current_dispxref->display_id;
    my $current_source = $current_dispxref->dbname;
    my $current_xrefid = $current_dispxref->dbID;

    #double check it's not an HGNC xref
    if ($current_source eq 'HGNC') {
      $support->log_warning("$gsi ($old_name->$new_name)) already has an HGNC xref, needs checking so skipping\n");
      next;
    }
    #double check it's the right one
    if ($current_name ne $old_name) {
      $support->log_warning("$gsi has a different name in the file ($old_name) than in the db($current_name), needs checking so skipping\n");
      next;
    }
    #check there's none by this name already
    if ( @{$ga->fetch_all_by_display_label($new_name)} ) {
      my $stable_ids = join ',', map { $_->stable_id } @{$ga->fetch_all_by_display_label($new_name)};
      $support->log_warning("$gsi ($old_name->$new_name) - can retrieve existing gene(s) from Vega with the new name ($new_name) already ($stable_ids), needs checking so skipping\n");
      next;
    }

    $support->log("Updating name of $gsi ($old_name --> $new_name), changing description, and adding synonym for old name\n",1);

    if (! $support->param('dry_run')) {
      my $c = $sth_xref->execute($new_name,$current_xrefid);
      warn $c;
      $c = $sth_desc->execute($desc,$gsi);
      warn $c;
      $c = $sth_ga->execute($new_name,$old_name,$g_dbID);
      warn $c;
      $c = $sth_syn->execute($g_dbID,$old_name);
      warn $c;
    }
  }
}

$support->finish_log;
