#!/usr/bin/env perl
# Copyright [2018-2019] EMBL-European Bioinformatics Institute
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

hide_non_havana_genes.pl

=head1 SYNOPSIS

hide_non_havana_genes.pl

=head1 DESCRIPTION

This script is used to make a gene invisible by clearing the is_current flag 
(and those of its child transcripts and exons).

Must provide a list of gene stable ids.

Here is an example commandline:

./hide_non_havana_genes.pl -dataset mouse

=head1 OPTIONS

    -dataset    dataset to use, e.g. human

    -dryrun     just list which genes would be affected
    -help|h     displays this documentation with PERLDOC

=head1 CONTACT

Michael Gray B<email> mg13@sanger.ac.uk

=cut

use strict;
use warnings;
die "... JOIN gene_stable_id ..."; # v65 schema

use Sys::Hostname;
use Try::Tiny;

use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Otter::Lace::Defaults;
use Bio::Vega::SliceLockBroker;
use Bio::Vega::Author;

{
    my $dataset_name;
    my $author = $ENV{USERNAME};
    my $dryrun;

    my $usage = sub { exec( 'perldoc', $0 ); };

    Bio::Otter::Lace::Defaults::do_getopt(
        'dataset=s'     => \$dataset_name,
        'author=s'      => \$author,
        'dryrun'        => \$dryrun,
        'h|help!'       => $usage,
    )
    or $usage->();

    $usage->() unless ($dataset_name and $author);

    local $0 = 'otter';     # for access to test_human

    # Client communicates with otter HTTP server
    my $cl = Bio::Otter::Lace::Defaults::make_Client();
    
    # DataSet interacts directly with an otter database
    my $ds = $cl->get_DataSet_by_name($dataset_name);

    # falls over on human_test, in _attach_DNA_DBAdaptor
    # my $otter_dba = $ds->get_cached_DBAdaptor;

    my $dba = $ds->make_Vega_DBAdaptor;

    my $gene_adaptor = $dba->get_GeneAdaptor;

    my $author_obj    = Bio::Vega::Author->new(-name => $author, -email => $author);

    my $list_genes = $dba->dbc->prepare(<<'__SQL__');
        SELECT 
            g.gene_id,
            gsi.stable_id
          FROM   gene           g
            JOIN gene_stable_id gsi USING (gene_id)
         WHERE
                is_current = 1
            AND source != 'havana'
__SQL__

    $list_genes->execute;

  GENE: while (my ($dbid, $sid) = $list_genes->fetchrow) {
    
      my $gene = $gene_adaptor->fetch_by_dbID($dbid);
      if (!$gene) {
          print STDOUT "Cannot fetch gene $sid ($dbid)\n";
          next GENE;
      }

      printf STDOUT ("%d\t%s\t%s\t%s\t",
                     $gene->dbID, $gene->stable_id,
                     $gene->source, $gene->biotype,
          );

# This is meaningless as fetch_latest... sorts by is_current first
# - would need to roll a sort-by-modified-date version to implement properly
#
#       my $latest_gene = $gene_adaptor->fetch_latest_by_stable_id($id);
#       unless ($latest_gene->dbID == $gene->dbID) {
#           printf STDOUT ("Gene is not latest version (latest gene_id %d) - SKIPPING\n");
#           next GSI;
#       }

      my $broker = Bio::Vega::SliceLockBroker->new
        (-hostname => hostname, -author => $author_obj, -adaptor => $dba);

      my $lock_ok;
      my $work = sub {
          $lock_ok = 1;
          $gene_adaptor->hide_db_gene($gene);
          print STDOUT "hidden\n";
          return;
      };

      try {
          if ($dryrun) {
              $lock_ok = 1;
              print STDOUT "dryrun\n";
          } else {
              $broker->lock_create_for_objects(hide_non_havana_genes => $gene);
              $broker->exclusive_work($work, 1);
          }
      } catch {
          if ($lock_ok) {
              print STDOUT "NOT HIDDEN\n";
              warning("Cannot hide $sid ($dbid)\n$_\n");
          } else {
              print STDOUT "LOCK FAIL\n";
              warning("Cannot lock for $sid\n$_\n");
          }
      } finally {
          $broker->unlock_all;
      };

  } # GSI

    exit 0;
}

__END__
