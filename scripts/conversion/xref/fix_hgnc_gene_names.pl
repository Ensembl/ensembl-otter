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


#note tis is the same as populate_alt_alleles
my $allowed_regions = [
    {
      '6'      => '28000000:34000000',
      '6-COX'  => 'all',
      '6-QBL'  => 'all',
      '6-APD'  => 'all',
      '6-MANN' => 'all',
      '6-MCF'  => 'all',
      '6-DBB'  => 'all',
      '6-SSTO' => 'all',
    },
    {
      '19'       => '54600000:55600000',
      '19-PGF_1' => 'all',
      '19-PGF_2' => 'all',
      '19-COX_1' => 'all',
      '19-COX_2' => 'all',
      '19-DM1A'  => 'all',
      '19-DM1B'  => 'all',
      '19-MC1A'  => 'all',
      '19-MC1B'  => 'all',
    },
  ];

#get new names from file and update each gene
$support->log("Retrieving details of genes from datafile...\n");
my $infile = $support->filehandle('<', $support->param('gene_file'));
my $c;
REC:
while (my $line = <$infile>) {
  next if ($line =~ /^#/);
  if ( my ( $gsi,$biotype,$sr,$old_name,$new_name,$desc ) = split '\t', $line) {
    $c++;
    chomp $desc;
    next if $gsi eq 'STABLE_ID';
#    next unless $gsi eq 'OTTHUMG00000031219';
    my $gene = $ga->fetch_by_stable_id($gsi);
    my $g_dbID = $gene->dbID;
    next unless $gene;

    my $current_dispxref = $gene->display_xref;
    my $current_name   = $current_dispxref->display_id;
    my $current_source = $current_dispxref->dbname;
    my $current_xrefid = $current_dispxref->dbID;
    my $current_location = $gene->seq_region_name;

    #double check it's not an HGNC xref
    if ($current_source eq 'HGNC') {
      $support->log_warning("$gsi ($old_name->$new_name)) already has an HGNC xref, needs checking so skipping\n",1);
      next;
    }
    #double check it's the right one
    if ($current_name ne $old_name) {
  #    $support->log_warning("$gsi has a different name in the file ($old_name) than in the db($current_name), needs checking so skipping\n",1);
  #    next;
    }
    #check there's none by this name already.
    my @genes = @{$ga->fetch_all_by_display_label($new_name) || []};
    if (scalar  @genes > 1) {
      my $stable_ids = join ',', map { $_->stable_id } @genes;
      my $region;
      my $not_wanted = 0;
      #check that the current gene is on an allowed region
      foreach my $comparison (@{$allowed_regions}) {
        if ($region = $comparison->{$current_location}) {
          if ($region ne 'all') {
            my ($reg_start,$reg_end) = split ':',$region;
            #add a 50kbp buffer
            $reg_start -= 50000;
            $reg_end += 50000;
            my $gene_start = $gene->seq_region_start;
            my $gene_end = $gene->seq_region_end;
            warn "$gene_start -- $gene_end";
            warn "$reg_start -- $reg_end";
            if ( ($gene_start < $reg_end) && ($gene_end > $reg_start) ) {
              last;
            }
            else {
              $not_wanted = $current_location;
            }
          }
          else {
            last;
          }
        }
        else {
          $not_wanted = $current_location;
        }
      }
      if ($not_wanted) {
        $support->log_warning("$gsi on chr $not_wanted is not on a region that we want, therefore although we can retrieve existing gene(s) from Vega ($stable_ids) we cannot update the name of this (update would be $old_name->$new_name). Refer for manual checking\n",1);
        next REC;
      }

      else {
        my $stable_id;
        foreach my $g (@genes) {
          next if $not_wanted;
          my $chrom_name = $g->seq_region_name;
#          warn $chrom_name;
          foreach my $comparison (@{$allowed_regions}) {
#            warn Data::Dumper::Dumper($comparison);
            if (my $region = $comparison->{$chrom_name}) {
              if ($region ne 'all') {
                #only get genes that start or end within the defined region
                my ($reg_start,$reg_end) = split ':',$region;
                #add a 50kbp buffer
                $reg_start -= 50000;
                $reg_end += 50000;
                my $gene_start = $g->seq_region_start;
                my $gene_end = $g->seq_region_end;
#                warn "$gene_start -- $gene_end";
#                warn "$reg_start -- $reg_end";
                if ( ($gene_start < $reg_end) && ($gene_end > $reg_start) ) {
#                  warn "OK";
                  last;
                  #that's OK
                }
                else {
                  $not_wanted = $chrom_name;
                  $stable_id = $g->stable_id;
                }
              }
              else {
                last;
              }
            }
            else {
              $not_wanted = $chrom_name;
              $stable_id = $g->stable_id;
            }
          }
        }

        if ($not_wanted) {
          $support->log_warning("$gsi on chr $sr - can retrieve existing gene from Vega ($stable_id) with the new name ($new_name), however this is on an unwanted chromosome ($not_wanted) and cannot be updated (update would be $old_name->$new_name). Refer for manual checking\n",1);
          next REC;
        }
        else {
          $support->log_verbose("$gsi on chr $sr - can retrieve existing gene(s) from Vega ($stable_ids) with the new name ($new_name) but these are on regions we know to be OK.\n",1);
        }
      }
    }

    $support->log("Updating name of $gsi ($old_name --> $new_name), changing description, and adding synonym for old name\n",1);

    if (! $support->param('dry_run')) {
      my $c = $sth_xref->execute($new_name,$current_xrefid);
      $support->log_warning("xref update failed\n") unless $c;
      $c = $sth_desc->execute($desc,$gsi);
      $support->log_warning("desc update failed\n") unless $c;
      $c = $sth_ga->execute($new_name,$old_name,$g_dbID);
      $support->log_warning("gene attrib update failed\n") unless $c;
      $c = $sth_syn->execute($g_dbID,$old_name);
      $support->log_warning("synonym  update failed\n") unless $c;
    }
  }
}

$support->finish_log;
