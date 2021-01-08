#!/usr/bin/env perl
# Copyright [2018-2021] EMBL-European Bioinformatics Institute
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


# In response to ticket #256630: Fwd: human broken genes fix
# Based on lace/list_attributes_by_target.pl

use warnings;
use strict;

use Carp;
use Bio::Otter::Lace::Defaults;

{
    my $dataset_name = undef;

    my $total = 0;
    my $quiet = 0;

    my $usage = sub { exec('perldoc', $0) };
    # This do_getopt() call is needed to parse the otter config files
    # even if you aren't giving any arguments on the command line.
    Bio::Otter::Lace::Defaults::do_getopt(
        'h|help!'       => $usage,
        'dataset=s'     => \$dataset_name,
        'quiet!'        => \$quiet,
        'total!'        => \$total,
        ) or $usage->();
    $usage->() unless $dataset_name;

    # Client communicates with otter HTTP server
    my $cl = Bio::Otter::Lace::Defaults::make_Client();

    # DataSet interacts directly with an otter database
    my $ds = $cl->get_DataSet_by_name($dataset_name);
    my $otter_dba = $ds->get_cached_DBAdaptor;

    my $list_transcripts = $otter_dba->dbc->prepare(q{
       SELECT
                g.gene_id,
                gsi.stable_id,
                gan.value,
                g.seq_region_start,
                g.seq_region_end,
                g.seq_region_strand,
                t.transcript_id,
                tsi.stable_id,
                tan.value,
                GROUP_CONCAT(at.code ORDER BY at.code SEPARATOR ';'),
                sr.name
        FROM
                transcript           t
           JOIN transcript_attrib    ta  ON t.transcript_id = ta.transcript_id
           JOIN attrib_type          at  ON ta.attrib_type_id = at.attrib_type_id
           JOIN transcript_stable_id tsi ON t.transcript_id = tsi.transcript_id
           JOIN gene                 g   ON t.gene_id = g.gene_id
           JOIN gene_stable_id       gsi ON g.gene_id = gsi.gene_id
           JOIN gene_attrib          gan ON     g.gene_id = gan.gene_id
                                            AND gan.attrib_type_id = (
                                                    SELECT attrib_type_id
                                                    FROM   attrib_type
                                                    WHERE  code = 'name'
                                                )
           JOIN transcript_attrib    tan ON     t.transcript_id = tan.transcript_id
                                            AND tan.attrib_type_id = (
                                                    SELECT attrib_type_id
                                                    FROM   attrib_type
                                                    WHERE  code = 'name'
                                                )
           JOIN seq_region           sr  ON g.seq_region_id = sr.seq_region_id
           JOIN seq_region_attrib    sra ON     sr.seq_region_id = sra.seq_region_id
                                            AND sra.attrib_type_id = (
                                                    SELECT attrib_type_id
                                                    FROM attrib_type
                                                    WHERE code = 'write_access'
                                                )
        WHERE
                at.code LIKE '%NF'
            AND ta.value = 1
            AND g.is_current = 1
            AND t.is_current = 1
            AND sra.value = 1
        GROUP BY tsi.stable_id
        ORDER BY sr.name, gsi.stable_id, tsi.stable_id
    });
    $list_transcripts->execute();

    my $count = 0;
    my $out_format = "%s,%s,%s,%d,%d,%d,%s,%s,%s\n";
    my $hdr_format = $out_format;
    $hdr_format =~ s/%d/%s/g;
    printf( $hdr_format,
            "Chromosome",
            "Gene name",
            "Gene stable id",
            "Gene start",
            "Gene end",
            "Gene strand",
            "Transcript name",
            "Transcript stable ID",
            "NF attributes"
        ) unless $quiet;

    while (my ($gid,
               $gene_sid,
               $gene_name,
               $gene_start,
               $gene_end,
               $gene_strand,
               $tid,
               $transcript_sid,
               $transcript_name,
               $attribs,
               $seq_region_name) = $list_transcripts->fetchrow()) {
        ++$count;
        printf( $out_format,
                $seq_region_name,
                $gene_name,
                $gene_sid,
                $gene_start,
                $gene_end,
                $gene_strand,
                $transcript_name,
                $transcript_sid,
                $attribs,
            ) unless $quiet;
    }
    printf "Total: %d\n", $count if $total;

}



__END__

=head1 NAME - start_end_not_found_genes.pl

=head1 SYNOPSIS

start_end_not_found_genes -dataset <DATASET NAME> [-quiet] [-total]

=head1 DESCRIPTION

Find genes via transcripts where a start- or end-not-found attribute
is set.

=head1 EXAMPLE

  start_end_not_found.pl --dataset=human

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

