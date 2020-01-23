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

unhide_gene.pl

=head1 SYNOPSIS

unhide_gene.pl

=head1 DESCRIPTION

This script is used to make a gene visible again, by setting the is_current flag
(and those of its child transcripts and exons).

The most recently modified non_current gene will be rendered visible.

Must provide a list of gene stable ids.

Here is an example commandline:

./unhide_gene.pl -dataset mouse -stable_id OTTMUSG00000016621,OTTMUSG00000001145

=head1 OPTIONS

    -dataset    dataset to use, e.g. human

    -stable_id  list of gene stable ids, comma separated
    -force      proceed without user confirmation
    -help|h     displays this documentation with PERLDOC

=head1 CONTACT

Michael Gray B<email> mg13@sanger.ac.uk

=cut

use strict;
use warnings;

use Sys::Hostname;
use Try::Tiny;

use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Otter::Lace::Defaults;
use Bio::Vega::SliceLockBroker;

{
    my $dataset_name;
    my @ids;
    my $force;

    my $usage = sub { exec( 'perldoc', $0 ); };

    Bio::Otter::Lace::Defaults::do_getopt(
        'dataset=s'     => \$dataset_name,
        'stable_id=s'   => \@ids,
        'force'         => \$force,
        'h|help!'       => $usage,
    )
    or $usage->();

    $usage->() unless ($dataset_name and @ids);

    local $0 = 'otter';     # for access to test_human

    # Client communicates with otter HTTP server
    my $cl = Bio::Otter::Lace::Defaults::make_Client();
    
    # DataSet interacts directly with an otter database
    my $ds = $cl->get_DataSet_by_name($dataset_name);

    # falls over on human_test, in _attach_DNA_DBAdaptor
    # my $otter_dba = $ds->get_cached_DBAdaptor;

    my $dba = $ds->make_Vega_DBAdaptor;

    my $gene_adaptor = $dba->get_GeneAdaptor;

    my @sids;
    foreach my $id_list (@ids) { push(@sids , split(/,/x, $id_list)); }

  GSI: foreach my $id (@sids) {
    
      my $gene = $gene_adaptor->fetch_latest_by_stable_id($id);
      if (!$gene) {
          print STDOUT "Cannot fetch gene stable id $id\n";
          next GSI;
      }

      printf STDOUT ("%s ID:%d Slice:%s <%d-%d:%d> Biotype:%s Source:%s is_current:%s\n",
                     $id, $gene->dbID,
                     $gene->seq_region_name, $gene->seq_region_start, $gene->seq_region_end, $gene->strand,
                     $gene->biotype, $gene->source, $gene->is_current ? 'yes':'no',
          );

      if ($gene->is_current) {
          print STDOUT "Gene $id already current, cannot unhide\n";
          next GSI;
      }

      if ($force || &proceed() =~ /^y$|^yes$/x ) {
          my $broker = Bio::Vega::SliceLockBroker->new
            (-hostname => hostname, -author => 'for_uid', -adaptor => $dba);

          my $lock_ok;
          my $work = sub {
              $lock_ok = 1;
              $gene_adaptor->unhide_db_gene($gene);
              print STDOUT "gene_stable_id $id is now visible\n";
              return;
          };

          try {
              $broker->lock_create_for_objects("unhide_gene.pl" => $gene);
              $broker->exclusive_work($work, 1);
          } catch {
              if ($lock_ok) {
                  warning("Cannot unhide $id\n$_\n");
              } else {
                  warning("Cannot lock for $id\n$_\n");
              }
          } finally {
              $broker->unlock_all;
          };
      }
  } # GSI

    exit 0;
}

sub proceed {
    print STDOUT "make this gene visible ? [no]";
    my $answer = <STDIN>;chomp $answer;
    $answer ||= 'no';
    return $answer;
}

__END__
