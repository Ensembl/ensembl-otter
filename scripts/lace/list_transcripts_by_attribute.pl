#!/usr/bin/env perl
# Copyright [2018-2023] EMBL-European Bioinformatics Institute
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


# In response to ticket #193917: List of NMD exceptions

use warnings;
use strict;

use Carp;
use Bio::Otter::Lace::Defaults;
use Bio::Otter::Server::Config;
use Bio::Otter::Utils::EnsEMBL;

{
    my $dataset_name = undef;
    my $attrib_pattern = undef;
    my $attrib_code = 'remark';

    my $total = 0;
    my $quiet = 0;
    my $ensembl_ids = 0;

    my $usage = sub { exec('perldoc', $0) };
    # This do_getopt() call is needed to parse the otter config files
    # even if you aren't giving any arguments on the command line.
    Bio::Otter::Lace::Defaults::do_getopt(
        'h|help!'       => $usage,
        'dataset=s'     => \$dataset_name,
        'attrib=s'      => \$attrib_pattern,
        'code:s'        => \$attrib_code,
        'ensembl!'      => \$ensembl_ids,
        'quiet!'        => \$quiet,
        'total!'        => \$total,
        ) or $usage->();
    $usage->() unless ($dataset_name and $attrib_pattern);

    # Go direct, not via http to server.
    my $ds = Bio::Otter::Server::Config->SpeciesDat->dataset($dataset_name);
    my $otter_dba = $ds->otter_dba;

    my $list_transcripts = $otter_dba->dbc->prepare(q{
        SELECT
                g.gene_id,
                g.stable_id,
                gan.value,
                t.transcript_id,
                t.stable_id,
                tan.value,
                ta.value,
                sr.name
        FROM
                transcript           t
           JOIN transcript_attrib    ta  USING (transcript_id)
           JOIN gene                 g   ON t.gene_id = g.gene_id
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
        WHERE
                t.is_current = 1
            AND ta.value LIKE ?
            AND ta.attrib_type_id = (
                                     SELECT attrib_type_id
                                     FROM   attrib_type
                                     WHERE  code = ?
                                    )
        ORDER BY g.stable_id, t.stable_id
    });
    $list_transcripts->execute($attrib_pattern, $attrib_code);

    my $count = 0;
    my $out_format;
    my $ensembl_utils;

    unless ($quiet) {
        if ($ensembl_ids) {
            $out_format = "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n";
            printf(
                $out_format,
                "Chromosome", "Gene_name", "OTT_id", "ENS_id", "Transcript_name", "OTT_id", "ENS_id", "Attribute",
            );
            $ensembl_utils = Bio::Otter::Utils::EnsEMBL->new($ds);
        } else {
            $out_format = "%s\t%s\t%s\t%s\t%s\t%s\n";
            printf(
                $out_format,
                "Chromosome", "Gene_name", "stable_id", "Transcript_name", "stable_id", "Attribute",
                );
        }
    }

    while (my ($gid, $gene_sid, $gene_name,
           $tid, $transcript_sid, $transcript_name,
           $attrib_value, $seq_region_name) = $list_transcripts->fetchrow()) {

        ++$count;

        unless ($quiet) {
            if ($ensembl_ids) {

                my $ens_gene_sids =       join(';', $ensembl_utils->stable_ids_from_otter_id($gene_sid)) || '';
                my $ens_transcript_sids = join(';', $ensembl_utils->stable_ids_from_otter_id($transcript_sid)) || '';

                printf( $out_format,
                        $seq_region_name, $gene_name, $gene_sid, $ens_gene_sids,
                        $transcript_name, $transcript_sid, $ens_transcript_sids,
                        $attrib_value,
                    );
            } else {
                printf( $out_format,
                        $seq_region_name, $gene_name, $gene_sid,
                        $transcript_name, $transcript_sid,
                        $attrib_value,
                    );
            }
        }

    }

    printf "Total: %d\n", $count if $total;

}



__END__

=head1 NAME - list_transcripts_by_attribute.pl

=head1 SYNOPSIS

list_transcripts_by_attribute -dataset <DATASET NAME> -attrib <ATTRIB PATTERN>
                              [-code <ATTRIB CODE>] [-quiet] [-total] [-ensembl]

=head1 DESCRIPTION

Checks for current transcripts having the specified atttribute value
in an attribute of the specified code.

The attribute value can contain SQL wildcards.
The attribute code defaults to 'remark'.

The -ensembl flag looks up EnsEMBL stable ids for genes and transcripts
and adds these columns to the output.

=head1 EXAMPLE

  list_transcripts_by_attribute.pl --dataset=mouse --attrib='NMD__xception'

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

