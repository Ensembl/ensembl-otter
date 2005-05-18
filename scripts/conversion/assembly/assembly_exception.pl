#!/usr/local/bin/perl

=head1 NAME

assembly_exception.pl - determine and resolve assembly exceptions

=head1 SYNOPSIS

    assembly_exception.pl [options]

    General options:
        --dbname, db_name=NAME              use database NAME
        --host, --dbhost, --db_host=HOST    use database host HOST
        --port, --dbport, --db_port=PORT    use database port PORT
        --user, --dbuser, --db_user=USER    use database username USER
        --pass, --dbpass, --db_pass=PASS    use database passwort PASS
        --driver, --dbdriver, --db_driver=DRIVER    use database driver DRIVER
        --conffile, --conf=FILE             read parameters from FILE
        --logfile, --log=FILE               log to FILE (default: *STDOUT)
        -i, --interactive                   run script interactively
                                            (default: true)
        -n, --dry_run, --dry                don't write results to database
        -h, --help, -?                      print help (this message)

=head1 DESCRIPTION

This script checks a schema 19 database for contigs shared between different
chromosomes and optionally resolves the problem by creating appropriate
assembly_exception entries. It must be run before asmtype2chrname.pl.

=head1 LICENCE

This code is distributed under an Apache style licence:
Please see http://www.ensembl.org/code_licence.html for details

=head1 AUTHOR

Patrick Meidl <pm2@sanger.ac.uk>
Based on code by Tim Hubbard <th@sanger.ac.uk>

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

$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

# parse options
$support->parse_common_options(@_);

if ($support->param('help') or $support->error) {
    warn $support->error if $support->error;
    pod2usage(1);
}

# ask user to confirm parameters to proceed
$support->confirm_params;

# get log filehandle and print heading and parameters to logfile
$support->log_filehandle('>>');
$support->log($support->init_log);

# get dbadaptors
my $dba = $support->get_database('ensembl');
my $dbh = $dba->dbc->db_handle;

# get assembly information for all contigs
my $sql = qq(
    SELECT c.name, a.type, a.chr_start, a.chr_end
    FROM assembly a, contig c
    WHERE a.contig_id = c.contig_id
);
my $sth = $dbh->prepare($sql);
$sth->execute;
my %contig;
while (my @row = $sth->fetchrow_array()){
    my($contig, $type, $chst, $ched) = @row;
    $contig{$contig}->{$type} = [ $chst, $ched ];
}

# identify shared contigs (used in two or more assembly.types)
my %dcontig;
foreach my $contig (keys %contig){
    if(scalar(keys %{$contig{$contig}}) > 1){
        foreach my $type (keys %{ $contig{$contig} }){
            my ($chst, $ched) = @{ $contig{$contig}->{$type} };
            $dcontig{$type}->{$contig} = [ $chst, $ched ];
        }
    }
}

my @shared;
my %ucontig;
foreach my $type (sort keys %dcontig){
    foreach my $contig (sort {$dcontig{$type}->{$a}->[0] <=> $dcontig{$type}->{$b}->[0]} keys %{ $dcontig{$type} }){
        # only process each contig once
        next if $ucontig{$contig};
        $ucontig{$contig} = 1;

        my ($chst, $ched) = @{ $dcontig{$type}->{$contig} };

        # look for a match for $type
        my $match = 0;
        my $mxi = scalar(@shared);
        for (my $i = 0; $i < $mxi; $i++) {
            if ($shared[$i]->{$type}) {
                my ($chst2, $ched2, @contigs) = @{ $shared[$i]->{$type} };
                if ($chst == $ched2+1) {
                    $shared[$i]->{$type} = [ $chst2, $ched, @contigs, $contig ];
                    $match = 1;
                    $mxi = $i;
                    last;
                }
            }
        }
        if ($match) {
            #print " old $mxi [$chst-$ched]\n";
        } else {
            $shared[$mxi]->{$type} = [ $chst, $ched, $contig ];
        }
        # save match for other $types
        foreach my $type2 (sort keys %{ $contig{$contig} }) {
            next if $type eq $type2;
            my ($chst, $ched) = @{ $contig{$contig}->{$type2} };
            if ($shared[$mxi]->{$type2}) {
                my ($chst2, $ched2, @contigs) = @{ $shared[$mxi]->{$type2} };
                if ($chst == $ched2+1) {
                    $shared[$mxi]->{$type2}=[ $chst2, $ched, @contigs, $contig ];
                }
            } else {
                $shared[$mxi]->{$type2} = [ $chst, $ched, $contig ];
            }
        }
    }
}

# report
my $mxi = scalar(@shared);
my %pairs;
if ($mxi > 0) {
    $support->log("The following $mxi regions are shared between VEGA sets:\n");
    my $ri = 0;
    my %total;
    for (my $i = 0; $i < $mxi; $i++) {
        $ri++;
        $support->log("REGION $ri:\n", 1);
        my @types;
        foreach my $type (sort keys %{ $shared[$i] }) {
            my ($chst, $ched, @contigs) = @{ $shared[$i]->{$type} };
            my $nc = scalar(@contigs);
            $total{$type} += $nc;
            $support->log("$type:$chst-$ched | $nc contigs\n", 2);
            map { $support->log("$_\n", 3) } @contigs;
            push @types, $type;
        }
        # remember sequence pairs for picking non-reference later
        $pairs{join("|", @types)} = \@types;
    }
    $support->log("\nTOTAL shared contigs:\n");
    foreach my $type (keys %total) {
        $support->log("$type: ".$total{$type}."\n", 1);
    }
    $support->log("\n");
} else {
    $support->log("No shared regions found.\n");
    $support->log($support->finish_log);
    exit;
}

# ask user if he wants to process shared contigs
exit unless $support->user_proceed("Would you like to create assembly_exception entries for the shared regions?");

# create assembly_exception table
unless ($support->param('dry_run')) {
    $support->log("\nCreating assembly_exception table...\n");
    $dbh->do(qq{
        CREATE TABLE assembly_exception (

          assembly_exception_id       INT(10) UNSIGNED NOT NULL AUTO_INCREMENT,
          seq_region_id               INT NOT NULL,
          seq_region_start            INT NOT NULL,
          seq_region_end              INT NOT NULL, 
          exc_type                    ENUM('HAP', 'PAR') NOT NULL,
          exc_seq_region_id           INT NOT NULL, 
          exc_seq_region_start        INT NOT NULL, 
          exc_seq_region_end          INT NOT NULL,
          ori                         INT NOT NULL,

          PRIMARY KEY (assembly_exception_id),

          KEY sr_idx (seq_region_id, seq_region_start),
          KEY ex_idx (exc_seq_region_id, exc_seq_region_start)

        ) TYPE=MyISAM;
    });
    $support->log("Done.\n");
}

# populate assembly_exception for the non-reference sequence
$support->log("\nProcessing shared regions...\n");
# first, get chromosome_ids for all sequences involved
my $all_types = join("', '", keys %dcontig);
my $sth1 = $dbh->prepare(qq{
    SELECT  distinct(a.type), c.name, c.chromosome_id
    FROM    assembly a, chromosome c
    WHERE   a.chromosome_id = c.chromosome_id
    AND     a.type IN ('$all_types')
});
$sth1->execute;
my %chr_ids;
while (my ($a_type, $chr_name, $chr_id) = $sth1->fetchrow_array) {
    $chr_ids{$a_type} = $chr_id;
}

my $sth2 = $dbh->prepare(qq(
    INSERT INTO assembly_exception
        (
        seq_region_id, seq_region_start, seq_region_end,
        exc_type,
        exc_seq_region_id, exc_seq_region_start, exc_seq_region_end,
        ori
        )
    VALUES (?, ?, ?, ?, ?, ?, ?, ?)
));

# foreach region pair, decide which will be the non-reference sequence
my %nonref;
print "\nPlease pick the NON-reference sequence (will be stored as\n";
print "assembly_exception) for each of the following pairs.\n";
print "Enter 1 or 2 for first or second sequence.\n";
foreach my $pair (keys %pairs) {
    print "    $pair: ";
    my $input = <>;
    chomp $input;
    while (!($input and ($input == 1 or $input == 2))) {
        print "You must enter 1 or 2!\n";
        print "    $pair: ";
        $input = <>;
        chomp $input;
    }
    $input -= 1;
    my $ref = $pairs{$pair}->[1 - 1*$input];
    my $nonref = $pairs{$pair}->[$input];
    $support->log("\n");

    # loop over all region pairs
    for (my $i = 0; $i < scalar(@shared); $i++) {
        # add entries to assembly_exception for non-reference
        next unless ($shared[$i]->{$ref} and $shared[$i]->{$nonref});
        my ($ref_start, $ref_end) = @{ $shared[$i]->{$ref} };
        my ($nonref_start, $nonref_end, @nonref_contigs) = @{ $shared[$i]->{$nonref} };
        $support->log("REGION ".($i+1)." ($nonref:$nonref_start-$nonref_end):\n", 1);
        # check for exceptions with non-matching lengths
        my $nonref_length = $nonref_end - $nonref_start + 1;
        my $ref_length = $ref_end - $ref_start + 1;
        unless ($nonref_length == $ref_length) {
            $support->log_warning("Non-matching length in assembly_exception mapping:\n", 2);
            $support->log("seq_region: $chr_ids{$nonref}:$nonref_start-$nonref_end\n", 3);
            $support->log("exc_seq_region: $chr_ids{$ref}:$ref_start-$ref_end\n", 3);
            $support->log("Please fix manually by investigating assembly_backup.\n", 2);
        }
        
        # store assembly_exception data
        $support->log("Storing assembly_exception data...\n", 2);
        unless ($support->param('dry_run')) {
            my $num = $sth2->execute(
                $chr_ids{$nonref}, $nonref_start, $nonref_end,
                'PAR',
                $chr_ids{$ref}, $ref_start, $ref_end,
                1
            );
            $support->log("Done inserting $num entries.\n", 2);
        }

        # delete entries from assembly for non-reference
        $support->log("Making backup copy of assembly table...\n", 2);
        unless ($support->param('dry_run')) {
            $dbh->do('DROP TABLE IF EXISTS assembly_backup');
            $dbh->do('CREATE TABLE assembly_backup SELECT * FROM assembly');
            $support->log("Done.\n", 2);
        }
        $support->log("Deleting from assembly...\n", 2);
        my $contig_list = join("', '", @nonref_contigs);
        unless ($support->param('dry_run')) {
            my $num = $dbh->do(qq(
                DELETE  a FROM assembly a, contig c
                WHERE   a.contig_id = c.contig_id
                AND     c.name IN ('$contig_list')
                AND     a.type = '$nonref'
            ));
            $support->log("Done deleting $num entries.\n", 2);
        }
    }
}

$support->log("Please delete assembly_backup once you've investigated any errors.\n");

# finish log
$support->log($support->finish_log);


