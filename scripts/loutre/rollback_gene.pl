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

rollback_gene.pl

=head1 DESCRIPTION

This script is used to switch a gene back to its previous version, if it
exists. First it delete the current gene then it makes the previous gene
current.

=head1 EXAMPLE

  ./rollback_gene.pl -dataset mouse -once -stable OTTMUSG00000016621,OTTMUSG00000001145

=head1 OPTIONS

=over 4

=item B<-stable>

List of gene stable ids, comma separated. Or multiple B<-stable> arguments can
be given, or a list of stable IDs can be supplied in files listed on the
command line.

=item B<-force>

Don't prompt the user for confirmation.

=item B<-once>

Roll back to the previous version only.

=item B<-help>

Displays this documentation.

=back

=head1 CONTACT

Mustapha Larbaoui B<ml6@sanger.ac.uk>

Refactored to use Bio::Otter::Lace::Defaults by James Gilbert B<jgrg@sanger.ac.uk>

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

use strict;
use warnings;

use Carp qw{ confess };
use Sys::Hostname qw{ hostname };
use Try::Tiny;

use Bio::Otter::Lace::Defaults;
use Bio::Otter::Server::Config;
use Bio::Vega::SliceLockBroker;

{
    my $dataset_name;
    my $force;
    my $once;
    my $author = (getpwuid($<))[0];
    my @stable_ids;

    # This do_getopt() call is needed to parse the otter config files
    # even if you aren't giving any arguments on the command line.
    Bio::Otter::Lace::Defaults::do_getopt(
        'dataset=s' => \$dataset_name,
        'force!'    => \$force,
        'once!'     => \$once,
        'stable=s'  => \@stable_ids,
    );
    Bio::Otter::Lace::Defaults::show_help() unless $dataset_name;

    if (@ARGV) {
        while (<>) {
            push(@stable_ids, split);
        }
    }

    # Split any comma separated lists of stable IDs
    @stable_ids = map { split /,/, $_ } @stable_ids;

    # DataSet interacts directly with an otter database
    my $ds = Bio::Otter::Server::Config->SpeciesDat->dataset($dataset_name);

    my $otter_dba = $ds->otter_dba;

    my $list_sth = $otter_dba->dbc->prepare(qq{
        SELECT g.gene_id
          , s.name
          , g.biotype
          , g.is_current
          , g.version
          , g.modified_date
          , a.author_name
          , g.description
        FROM gene g
          , gene_author ga
          , seq_region s
          , author a
        WHERE g.stable_id = ?
          AND s.seq_region_id = g.seq_region_id
          AND ga.gene_id = g.gene_id
          AND ga.author_id = a.author_id
        ORDER BY g.modified_date DESC
    });

    my $gene_adaptor = $otter_dba->get_GeneAdaptor;

    my $author_obj = Bio::Vega::Author->new(-name => $author, -email => $author);

  GSI: foreach my $id (@stable_ids) {
        print "Get information for gene_stable_id $id\n";
        my $genes = get_history($list_sth, $id);

        unless (@$genes) {
            warn("No such Gene stable ID '$id' in $dataset_name\n");
            next GSI;
        }

        my $current_gene_id = shift @$genes;

        warn("There is only one version of gene $id\n") unless @$genes;
      GENE: while (@$genes) {
            my $previous_gene_id = shift @$genes;
            my $cur_gene         = $gene_adaptor->fetch_by_dbID($current_gene_id);
            my $prev_gene        = $gene_adaptor->fetch_by_dbID($previous_gene_id);
            if ($force || proceed($current_gene_id) =~ /^y$|^yes$/) {

                my $broker = Bio::Vega::SliceLockBroker->new
                  (-hostname => hostname(), -author => $author_obj, -adaptor => $otter_dba);

                my $lock_ok;
                my $work = sub {
                    $lock_ok = 1;
                    $gene_adaptor->remove($cur_gene);
                    $gene_adaptor->resurrect($prev_gene);
                    print STDERR "gene_id $current_gene_id REMOVED !!!!!!\n";
                    return;
                };

                try {
                    printf STDERR "Locking gene slice %s <%d-%d>\n",
                      $cur_gene->seq_region_name,
                        $cur_gene->seq_region_start, $cur_gene->seq_region_end;
                    $broker->lock_create_for_objects
                      ("rollback_gene.pl" => $cur_gene, $prev_gene);
                    $broker->exclusive_work($work, 1);
                } catch {
                    if ($lock_ok) {
                        warn("Problem rolling back gene\n$_\n");
                    } else {
                        warn("Problem locking gene slice with author name $author\n$_\n");
                    }
                } finally {
                    $broker->unlock_all;
                };

            }
            else {
                last GENE;
            }
            $current_gene_id = $previous_gene_id;

            last GENE if $once;
        }
    }
}

sub proceed {
    my ($id) = @_;
    print STDERR "remove gene $id ? [no] ";
    my $answer = <STDIN>;
    chomp $answer;
    $answer ||= 'no';
    return $answer;
}

sub get_history {
    my ($sth, $sid) = @_;

    $sth->execute($sid);
    
    my $format = "%8d  %-10.10s  %-20.20s  %2d  %2d  %-19s  %-6.6s  %s\n";
    if ($sth->rows) {
        my $header_format = $format;
        $header_format =~ s/[a-z]/s/g;
        printf STDERR $header_format, qw{ gene_id assembly biotype C V modified_date author description };
    }

    my $gene_ids = [];
    while (my @arr = $sth->fetchrow_array) {
        printf STDERR $format, @arr;
        push @$gene_ids, $arr[0];
    }

    return $gene_ids;
}
