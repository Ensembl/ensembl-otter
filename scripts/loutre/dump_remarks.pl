#!/usr/bin/env perl
# Copyright [2018-2024] EMBL-European Bioinformatics Institute
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

use warnings;
use strict;

use Carp;
use Bio::Otter::Lace::Defaults;

{
    my $dataset_name = undef;

    my $total = 0;
    my $quiet = 0;
    my $limit = 0;

    my $usage = sub { exec('perldoc', $0) };
    # This do_getopt() call is needed to parse the otter config files
    # even if you aren't giving any arguments on the command line.
    Bio::Otter::Lace::Defaults::do_getopt(
        'h|help!'       => $usage,
        'dataset=s'     => \$dataset_name,
        'limit=i'       => \$limit,
        'quiet!'        => \$quiet,
        'total!'        => \$total,
        ) or $usage->();
    $usage->() unless $dataset_name;

    # Client communicates with otter HTTP server
    my $cl = Bio::Otter::Lace::Defaults::make_Client();

    # DataSet interacts directly with an otter database
    my $ds = $cl->get_DataSet_by_name($dataset_name);
    my $otter_dba = $ds->get_cached_DBAdaptor;

    # Wouldn't DBIC be nicer???
    my $gsi_join = q{
           JOIN gene_stable_id       gsi ON g.gene_id = gsi.gene_id
    };

    my $gene_name_join = q{
           JOIN gene_attrib          gan ON     g.gene_id = gan.gene_id
                                            AND gan.attrib_type_id = (
                                                    SELECT attrib_type_id
                                                    FROM   attrib_type
                                                    WHERE  code = 'name'
                                                )
    };

    my $gene_remark_joins = q{
           LEFT JOIN gene_attrib          gar ON     g.gene_id = gar.gene_id
                                                AND gar.attrib_type_id = (
                                                        SELECT attrib_type_id
                                                        FROM   attrib_type
                                                        WHERE  code = 'remark'
                                                    )
           LEFT JOIN gene_attrib          gah ON     g.gene_id = gah.gene_id
                                                AND gah.attrib_type_id = (
                                                        SELECT attrib_type_id
                                                        FROM   attrib_type
                                                        WHERE  code = 'hidden_remark'
                                                    )
    };

    my $transcript_remark_joins = q{
           LEFT JOIN transcript_attrib    tar ON     t.transcript_id = tar.transcript_id
                                          AND tar.attrib_type_id = (
                                                  SELECT attrib_type_id
                                                  FROM   attrib_type
                                                  WHERE  code = 'remark'
                                              )
           LEFT JOIN transcript_attrib    tah ON     t.transcript_id = tah.transcript_id
                                          AND tah.attrib_type_id = (
                                                  SELECT attrib_type_id
                                                  FROM   attrib_type
                                                  WHERE  code = 'hidden_remark'
                                              )
    };

    my $writable_seq_region_join = q{
           JOIN seq_region           sr  ON g.seq_region_id = sr.seq_region_id
           JOIN seq_region_attrib    sra ON     sr.seq_region_id = sra.seq_region_id
                                            AND sra.attrib_type_id = (
                                                    SELECT attrib_type_id
                                                    FROM attrib_type
                                                    WHERE code = 'write_access'
                                                )
    };

    my $gene_fields = q{
            g.gene_id,
            sr.name AS sr_name,
            gsi.stable_id AS gene_stable_id
    };

    my $standard_fields = q{
                gan.value,
                g.seq_region_start,
                g.seq_region_end,
                g.seq_region_strand
    };

    my $list_genes_sth = $otter_dba->dbc->prepare(qq{
      ( SELECT
${gene_fields}
        FROM
                gene                 g
${gsi_join}
${gene_remark_joins}
${writable_seq_region_join}
        WHERE
                (gar.value IS NOT NULL OR gah.value IS NOT NULL)
            AND g.is_current = 1
            AND sra.value = 1
      )
    UNION
      ( SELECT
${gene_fields}
        FROM
                     transcript           t
${transcript_remark_joins}
           JOIN gene                 g   ON t.gene_id = g.gene_id
${gsi_join}
${writable_seq_region_join}
        WHERE
                (tar.value IS NOT NULL OR tah.value IS NOT NULL)
            AND t.is_current = 1
            AND g.is_current = 1
            AND sra.value = 1
      )
    ORDER BY
        sr_name,
        gene_stable_id
    });

    my $gene_remarks_sth = $otter_dba->dbc->prepare(qq{
        SELECT
            ${standard_fields},
            gar.value,
            gah.value
        FROM
                gene                 g
${gsi_join}
${gene_name_join}
${gene_remark_joins}
        WHERE
                g.gene_id = ?
            AND (gar.value IS NOT NULL OR gah.value IS NOT NULL)
        ORDER BY
            gar.value,
            gah.value
    });

    my $transcript_remarks_sth = $otter_dba->dbc->prepare(qq{
        SELECT
            ${standard_fields},
            tsi.stable_id,
            tan.value,
            tar.value,
            tah.value
        FROM
                gene                 g
${gsi_join}
${gene_name_join}
           JOIN transcript           t   ON t.gene_id = g.gene_id
           JOIN transcript_stable_id tsi ON tsi.transcript_id = t.transcript_id
           JOIN transcript_attrib    tan ON     t.transcript_id = tan.transcript_id
                                            AND tan.attrib_type_id = (
                                                    SELECT attrib_type_id
                                                    FROM   attrib_type
                                                    WHERE  code = 'name'
                                                )
${transcript_remark_joins}
        WHERE
                g.gene_id = ?
            AND t.is_current = 1
            AND (tar.value IS NOT NULL OR tah.value IS NOT NULL)
        ORDER BY
            tsi.stable_id,
            tar.value,
            tah.value
    });

    $list_genes_sth->execute();

    my $out_format = "%s,%s,%s,%d,%d,%d,%s,%s,%s,%s,%s,%s\n";
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
            "Gene remark",
            "Gene hidden remark",
            "Transcript remark",
            "Transcript hidden remark",
        ) unless $quiet;

    my ($gene_count, $gene_remark_count, $transcript_remark_count) = (0, 0, 0);

    while (my ($gene_id, $seq_region_name, $gene_sid) = $list_genes_sth->fetchrow) {

        ++$gene_count;

        $gene_remarks_sth->execute($gene_id);
        while (my ($gene_name,
                   $gene_start,
                   $gene_end,
                   $gene_strand,
                   $gene_remark,
                   $gene_hidden_remark) = $gene_remarks_sth->fetchrow) {

            ++$gene_remark_count;
            printf( $out_format,
                    $seq_region_name,
                    $gene_name,
                    $gene_sid,
                    $gene_start,
                    $gene_end,
                    $gene_strand,
                    '',         # transcript_name
                    '',         # transcript_sid
                    quote_remark($gene_remark, 'remark', $gene_sid, '-'),
                    quote_remark($gene_hidden_remark, 'hidden_remark', $gene_sid, '-'),
                    '',         # transcript_remark
                    '',         # transcript_hidden_remark
                ) unless $quiet;
        }

        $transcript_remarks_sth->execute($gene_id);
        while (my ($gene_name,
                   $gene_start,
                   $gene_end,
                   $gene_strand,
                   $transcript_sid,
                   $transcript_name,
                   $transcript_remark,
                   $transcript_hidden_remark) = $transcript_remarks_sth->fetchrow) {

            ++$transcript_remark_count;
            printf( $out_format,
                    $seq_region_name,
                    $gene_name,
                    $gene_sid,
                    $gene_start,
                    $gene_end,
                    $gene_strand,
                    $transcript_name,
                    $transcript_sid,
                    '',         # gene_remark
                    '',         # gene_hidden_remark
                    quote_remark($transcript_remark, 'remark', $gene_sid, $transcript_sid),
                    quote_remark($transcript_hidden_remark, 'hidden_remark', $gene_sid, $transcript_sid),
                ) unless $quiet;
        }

        last if $limit and ($gene_remark_count + $transcript_remark_count) > $limit;
    }

    printf("Total genes: %d, gene remarks: %d, transcript remarks: %d\n",
           $gene_count, $gene_remark_count, $transcript_remark_count      ) if $total;
}

sub quote_remark {
    my ($remark, $what, $g_sid, $t_sid) = @_;
    return '' unless defined($remark);

    $remark =~ s/"/&quot;/g;
    return sprintf('"%s"', $remark);
}

__END__

=head1 NAME - dump_remarks.pl

=head1 SYNOPSIS

dump_remarks.pl -dataset <DATASET NAME> [-quiet] [-total]

=head1 DESCRIPTION

Dump all gene and transcript remarks and hidden remarks,
gene by gene.

=head1 EXAMPLE

  dump_remarks.pl --dataset=human

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

