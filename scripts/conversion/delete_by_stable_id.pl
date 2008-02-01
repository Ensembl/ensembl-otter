#!/usr/local/bin/perl

=head1 NAME

delete_by_stable_id.pl - filter internal annotation from a Vega or Ensembl db

=head1 SYNOPSIS

delete_by_stable_id.pl [options]

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

Specific options:

    --keep=FILE                         read list of stable IDs to *keep* from
                                        FILE
    --delete=FILE                       read list of stable IDs to *delete*
                                        from FILE
    --gene_stable_ids                   IDs of genes to delete
    --find_missing                      print list of genes in infile but not in
                                        database
    --outfile=FILE                      write list of missing genes to FILE

    --schematype=TYPE                   assume either vega or ensembl schema

=head1 DESCRIPTION

Use this script to delete genes and/or transcripts and all associated
annotation (transcript, translations, xrefs, ...) from a Vega or Ensembl database.
The schema type can be provided as a command line argument or determined automaticaly
by the presence or abscence of the gene_info table.

You can provide either a list of gene_stable_ids to keep (--keep=FILE) or to
delete (--delete=FILE), where FILE is a list of stable IDs, one per line. It will
automatically determine whether a stable ID is a gene or a transcript. Alternatively
gene_stable_IDs can be provided on the command line.

The script also checks if any genes/transcripts in the list are not in the
database and optionally prints a list of these stable IDs (use --find_missing
and --outfile=FILE).

=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

=head1 AUTHOR

Steve Trevanion <st3@sanger.ac.uk>
Patrick Meidl <meidl@ebi.ac.uk>

=head1 CONTACT

Post questions to the EnsEMBL development list ensembl-dev@ebi.ac.uk

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use FindBin qw($Bin);
use vars qw($SERVERROOT);

BEGIN {
    $SERVERROOT = "$Bin/../../..";
    unshift(@INC, "$SERVERROOT/ensembl/modules");
    unshift(@INC, "$SERVERROOT/bioperl-live");
	unshift(@INC, "$SERVERROOT/ensembl-otter/scripts/conversion/modules");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use Deletion;

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
    'keep=s',
    'delete=s',
    'outfile=s',
    'find_missing',
	'schematype=s',
	'gene_stable_ids=s@'
);
$support->allowed_params(
    $support->get_common_params,
    'keep',
    'delete',
    'outfile',
    'find_missing',
    'schematype',
	'gene_stable_ids',
);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

$support->comma_to_list('gene_stable_ids');

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->init_log;

# connect to database and get adaptors
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;

# find out if we are dealing with an Ensembl or Vega schema
my $schema;
if ($schema = $support->param('schematype')) {
	unless ($schema eq 'vega' || $schema eq 'ensembl') {
		$support->log("schematype argument can only be \'ensembl\' or \'vega\'. Aborting\n");
		exit(0);
	}
}
else {
	my %tabs;
	map { $_ =~ s/`//g; $tabs{$_} = 1; } $dbh->tables;
	$schema = $tabs{'gene_author'} ? 'vega' : 'ensembl';
}

# sanity check: you can must choose to either keep or to delete
my ($action, $condition, $infile);
if ($support->param('keep')) {
    $infile = $support->param('keep');
    $action = 'keep';
    $condition = "NOT IN";
} elsif ($support->param('delete')) {
    $infile = $support->param('delete');
    $action = 'delete';
    $condition = "IN";
} elsif ($support->param('gene_stable_ids')) {
	$action = 'delete';
    $condition = "IN";
} else {
    $support->log_error("You must choose to either delete or keep genes by their stable_ids.\n");
}

# make sure user knows what he's doing
exit unless ($support->user_proceed("You decided to ".uc($action)." all genes and/or transcripts $condition the list provided from the $schema database. Are you sure you want to proceed?"));

my ($gene_stable_ids, $trans_stable_ids);
# read list of stable IDs to keep or delete
if ($support->param('gene_stable_ids')) {
	$gene_stable_ids = [$support->param('gene_stable_ids')];
	$trans_stable_ids = [];
}
else {
	($gene_stable_ids, $trans_stable_ids) = &read_infile($action, $infile); 
}

# sanity check: check if all genes in the list are also in the database
&check_missing($gene_stable_ids, $trans_stable_ids);

# nothing else to be done for dry runs
if ($support->param('dry_run')) {
    $support->log("Nothing else to be done for dry run. Aborting.\n");
    exit(0);
}

# delete genes
my $deleted = 0;
$deleted += &delete_genes($gene_stable_ids, $schema, $condition);

# delete transcripts
if (@{$trans_stable_ids}) {
	$deleted += &delete_transcripts($trans_stable_ids, $schema, $condition);
}

# only try to delete exons and xrefs if you actually deleted genes and/or
# transcripts
if ($deleted) {
    # delete exons
    &Deletion::delete_exons($support,$dbh);

    # delete xrefs
    &Deletion::delete_xrefs($support,$dbh);

    # optimize tables
    &Deletion::optimize_tables($support,$dbh);
}

# finish logfile
$support->finish_log;


### END main ###


=head2 read_infile

  Arg[1]      : String $infile - name of file to read stable IDs from
  Example     : my ($gene_stable_ids) = &read_infile('/my/input/file.txt');
  Description : read list of stable IDs to keep or delete from file
  Return type : Arrayref - listref of stable IDs
  Exceptions  : none
  Caller      : internal

=cut

sub read_infile {
    my ($action, $infile) = @_;

    $support->log_stamped("Reading stable IDs to ".$action." from file...\n");

    my $in = $support->filehandle('<', $infile);
    my @gene_stable_ids = ();
    my @trans_stable_ids = ();
    while (<$in>) {
        chomp $_;
		my ($id) = $_ =~ /(\w+)/;
        if ($id =~ /^OTT...G/) {
            push @gene_stable_ids, $id;
        } elsif ($id =~ /^OTT...T/) {
            push @trans_stable_ids, $id;
        }
    }
    close($in);

    $support->log_stamped("Done reading ".scalar(@gene_stable_ids)." genes, ".scalar(@trans_stable_ids)." transcripts.\n\n");

    return \@gene_stable_ids, \@trans_stable_ids;
}

=head2 check_missing

  Arg[1]      : Arrayref $gene_stable_ids - listref of gene stable IDs
  Arg[2]      : Arrayref $trans_stable_ids - listref of transcript stable IDs
  Example     : &check_missing($gene_stable_ids, $trans_stable_ids);
  Description : Check if all genes/transcripts in the list are also in the
                database. Warn if this is not the case, and print list of
                missing stable IDs on request (use --find_missing and --outfile
                options).
  Return type : none
  Exceptions  : none
  Caller      : general

=cut

sub check_missing {
    my ($gene_stable_ids, $trans_stable_ids) = @_;

    $support->log("Checking for missing genes and/or transcripts...\n");

    # genes
    my $gsi_string = join("', '", @{ $gene_stable_ids });
    my $sql = qq(
        SELECT  stable_id
        FROM    gene_stable_id
        WHERE   stable_id IN ('$gsi_string')
    );
    my @genes_in_db = map { $_->[0] } @{ $dbh->selectall_arrayref($sql) || [] };
    my $gdiff = scalar(@{ $gene_stable_ids }) - scalar(@genes_in_db);

    # transcripts
    my $tsi_string = join("', '", @{ $trans_stable_ids });
    $sql = qq(
        SELECT  stable_id
        FROM    transcript_stable_id
        WHERE   stable_id IN ('$tsi_string')
    );
    my @trans_in_db = map { $_->[0] } @{ $dbh->selectall_arrayref($sql) || [] };
    my $tdiff = scalar(@{ $trans_stable_ids }) - scalar(@trans_in_db);
    
    if ($gdiff or $tdiff) {
        $support->log_warning("Not all genes and/or transcripts in the input file could be found in the db ($gdiff genes, $tdiff transcripts missing).\n");
        # print list of missing stable IDs
        if ($support->param('find_missing')) {
            $support->log("Printing list of missing stable IDs to file...\n", 1);
            my $out = $support->filehandle('>', $support->param('outfile'));

            # genes
            my %gseen;
            @gseen{@genes_in_db} = (1) x @genes_in_db;
            foreach my $gsi (@{ $gene_stable_ids }) {
                print $out "$gsi\n" unless $gseen{$gsi};
            }

            # transcripts
            my %tseen;
            @tseen{@trans_in_db} = (1) x @trans_in_db;
            foreach my $tsi (@{ $trans_stable_ids }) {
                print $out "$tsi\n" unless $tseen{$tsi};
            }

            $support->log("Done.\n", 1);

        # suggest to run with --find_missing option
        } else {
            $support->log("Please run the script with the --find_missing option and check to see what's wrong.\n");
        }

        # ask user if he wants to proceed regardless of the potential problem
        unless ($support->user_proceed("\nPotential data inconsistencies (see logfile). Would you like to proceed anyway?")) {
            exit(0);
        }
    }
    $support->log("Done.\n\n");
}

=head2 delete_genes

  Arg[1]      : Arrayref $gene_stable_ids - listref of gene stable IDs
  Arg[2]      : String $schema - db schema (ensembl|vega)
  Arg[3]      : String $condition - condition to use in WHERE clause (IN|NOT IN)
  Example     : my $deleted += &delete_genes($gene_stable_ids, 'vega', 'IN');
  Description : Deletes all genes (and associated transcripts and translations)
                in the list provided. Knows how to deal with Vega and Ensembl
                schemas.
  Return type : 0 if no genes to delete, number of records deleted otherwise
  Exceptions  : none
  Caller      : internal

=cut

sub delete_genes {
    my ($gene_stable_ids, $schema, $condition) = @_;

    unless ($gene_stable_ids) {
        $support->log("No genes to delete.\n");
        return(0);
    }

    $support->log_stamped("Deleting genes, transcripts and translations by stable ID (and their features, attributes and authors) ...\n");

    my $gsi_string = join("', '", @{ $gene_stable_ids });
    my $sql;
    if ($schema eq 'vega') {
        # delete statement for Vega schema
        $sql = qq(
            DELETE QUICK IGNORE
                    g,
                    gsi,
                    ga,
                    gau,
                    t,
                    tsi,
                    ta,
                    tau
                    tl,
                    tla,
                    tlsi,
                    e,
                    pf
            FROM
                    (((((((
                    ( gene g,
                    gene_stable_id gsi,
                    gene_author gau,
                    transcript t,
                    transcript_stable_id tsi,
                    transcript_author tau )
            LEFT JOIN
                    gene_attrib ga ON g.gene_id = ga.gene_id )
            LEFT JOIN
                    transcript_attrib ta ON t.transcript_id = ta.transcript_id )
            LEFT JOIN
                    evidence e ON t.transcript_id = e.transcript_id )
            LEFT JOIN
                    translation tl ON t.transcript_id = tl.transcript_id )
            LEFT JOIN
                    translation_attrib tla ON tl.translation_id = tla.translation_id )
            LEFT JOIN
                    translation_stable_id tlsi ON tl.translation_id = tlsi.translation_id )
            LEFT JOIN
                    protein_feature pf ON tl.translation_id = pf.translation_id )
            WHERE   gsi.stable_id $condition ('$gsi_string')
            AND     g.gene_id = gsi.gene_id
            AND     g.gene_id = gau.gene_id
            AND     t.gene_id = g.gene_id
            AND     t.transcript_id = tsi.transcript_id
            AND     t.transcript_id = tau.transcript_id
        );
    } else {
        # delete statement for Ensembl schema
        $sql = qq(
            DELETE QUICK IGNORE
                    g,
                    gsi,
                    ga,
                    t,
                    tsi,
                    ta,
                    tl,
                    tla,
                    tlsi,
                    pf
            FROM
                    ((((((
                    (gene g,
                    gene_stable_id gsi,
                    transcript t,
                    transcript_stable_id tsi)
            LEFT JOIN
                    gene_attrib ga ON g.gene_id = ga.gene_id )
            LEFT JOIN
                    transcript_attrib ta ON t.transcript_id = ta.transcript_id )
            LEFT JOIN
                    translation tl ON t.transcript_id = tl.transcript_id )
            LEFT JOIN
                    translation_attrib tla ON tl.translation_id = tla.translation_id )
            LEFT JOIN
                    translation_stable_id tlsi ON tl.translation_id = tlsi.translation_id )
            LEFT JOIN
                    protein_feature pf ON tl.translation_id = pf.translation_id )
            WHERE   gsi.stable_id $condition ('$gsi_string')
            AND     g.gene_id = gsi.gene_id
            AND     t.gene_id = g.gene_id
            AND     t.transcript_id = tsi.transcript_id
        );
    }
    my $num = $dbh->do($sql);
    $support->log_stamped("Done deleting $num records.\n\n");

    return($num);
}

=head2 delete_transcripts

  Arg[1]      : Arrayref $trans_stable_ids - listref of transcript stable IDs
  Arg[2]      : String $schema - db schema (ensembl|vega)
  Arg[3]      : String $condition - condition to use in WHERE clause (IN|NOT IN)
  Example     : my $deleted += &delete_transcripts($trans_stable_ids, 'vega', 'IN');
  Description : Deletes all transcripts (and associated translations) in the
                list provided. Knows how to deal with Vega and Ensembl schemas.
  Return type : 0 if no transcripts to delete, number of records deleted
                otherwise
  Exceptions  : none
  Caller      : internal

=cut

sub delete_transcripts {
    my ($trans_stable_ids, $schema, $condition) = @_;

    unless ($trans_stable_ids) {
        $support->log("No transcripts to delete.\n");
        return(0);
    }

    $support->log_stamped("Deleting transcripts by stable ID (and their translations) ...\n");

    my $tsi_string = join("', '", @{ $trans_stable_ids });
    my $sql;
    if ($schema eq 'vega') {
        # delete statement for Vega schema
        $sql = qq(
            DELETE QUICK IGNORE
                    t,
                    tsi,
                    ta,
                    tau
                    e,
                    tl,
                    tla,
                    tlsi,
                    pf
            FROM
                    (((((( 
                    ( transcript t,
                    transcript_stable_id tsi,
                    transcript_author tau )
            LEFT JOIN
                    transcript_attrib ta ON t.transcript_id = ta.transcript_id )
            LEFT JOIN
                    evidence e ON t.transcript_id = e.transcript_id )
            LEFT JOIN
                    translation tl ON t.transcript_id = tl.transcript_id )
            LEFT JOIN
                    translation_attrib tla ON tl.translation_id = tla.translation_id )
            LEFT JOIN
                    translation_stable_id tlsi ON tl.translation_id = tlsi.translation_id )
            LEFT JOIN
                    protein_feature pf ON tl.translation_id = pf.translation_id )
            WHERE   tsi.stable_id $condition ('$tsi_string')
            AND     t.transcript_id = tsi.transcript_id
            AND     t.transcript_id = tau.transcript_id
        );
    } else {
        # delete statement for Ensembl schema
        $sql = qq(
            DELETE QUICK IGNORE
                    t,
                    tsi,
                    ta,
                    tl,
                    tla,
                    tlsi,
                    pf
            FROM
                    (((((
                    (transcript t,
                    transcript_stable_id tsi)
            LEFT JOIN
                    transcript_attrib ta ON t.transcript_id = ta.transcript_id )
            LEFT JOIN
                    translation tl ON t.transcript_id = tl.transcript_id )
            LEFT JOIN
                    translation_attrib tla ON tl.translation_id = tla.translation_id )
            LEFT JOIN
                    translation_stable_id tlsi ON tlsi.translation_id = tl.translation_id )
            LEFT JOIN
                    protein_feature pf ON pf.translation_id = tl.translation_id )
            WHERE   tsi.stable_id $condition ('$tsi_string')
            AND     t.transcript_id = tsi.transcript_id
        );
    }
    my $num = $dbh->do($sql);
    $support->log_stamped("Done deleting $num records.\n\n");

    # now look for orphan genes and delete them
    $support->log_stamped("Looking for orphan genes...\n");
    $sql = qq(
        SELECT g.gene_id
        FROM gene g
        LEFT JOIN transcript t ON g.gene_id = t.gene_id
        WHERE t.gene_id IS NULL;
    );
    my @orphan_genes = map { $_->[0] } @{ $dbh->selectall_arrayref($sql) || [] };

    if (@orphan_genes) {
        $support->log_stamped("Deleting orphan genes...\n", 1);

        my $gi_string = join("', '", @orphan_genes);
        if ($schema eq 'vega') {
            # delete statement for Vega schema
            $sql = qq(
                DELETE QUICK IGNORE
                        g,
                        gsi,
                        ga,
                        gau,
                FROM
                        (
                        (gene g,
                        gene_stable_id gsi,
                        gene_author gau )
                LEFT JOIN
                        gene_attrib ga ON g.gene_id = ga.gene_id )
                WHERE   g.gene_id $condition ('$gi_string')
                AND     g.gene_id = gsi.gene_id
                AND     g.gene_id = gau.gene_id
            );
        } else {
            # delete statement for Ensembl schema
            $sql = qq(
                DELETE QUICK IGNORE
                        g,
                        gsi
                        ga
                FROM
                        gene g,
                        gene_stable_id gsi
                        gene_attrib ga
                WHERE   g.gene_id $condition ('$gi_string')
                AND     g.gene_id = gsi.gene_id
                AND     g.gene_id = gs.gene_id
            );
        }
        my $num1 = $dbh->do($sql);
        $num += $num1;
        $support->log_stamped("Done deleting $num1 records.\n", 1);
    } else {
        $support->log("No orphan genes found.\n", 1);
    }
    
    $support->log_stamped("Done.\n\n");

    return($num);
}

