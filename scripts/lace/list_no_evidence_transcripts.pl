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


use warnings;


use strict;
use Carp;
use IO::String;
use Bio::Otter::Lace::Defaults;
use Bio::SeqIO;

{
    my $dataset_name = undef;
    my $total = 0;
    my $quiet = 0;
    my $dump_seq = 0;
    my $list_attrs = 0;
    my $biotype_count = 0;

    my $usage = sub { exec('perldoc', $0) };
    # This do_getopt() call is needed to parse the otter config files
    # even if you aren't giving any arguments on the command line.
    Bio::Otter::Lace::Defaults::do_getopt(
        'h|help!'       => $usage,
        'dataset=s'     => \$dataset_name,
        'quiet!'        => \$quiet,
        'total!'        => \$total,
        'dumpseq!'      => \$dump_seq,
        'list_attrs!'   => \$list_attrs,
        'biotype_count!'=> \$biotype_count,
        ) or $usage->();
    $usage->() unless $dataset_name;

    if ($quiet and not $total) {
        carp "Using -quiet but not -total - no output will be produced!";
    }

    # Client communicates with otter HTTP server
    my $cl = Bio::Otter::Lace::Defaults::make_Client();
    
    # DataSet interacts directly with an otter database
    my $ds = $cl->get_DataSet_by_name($dataset_name);
    my $otter_dba = $ds->get_cached_DBAdaptor;

    my $transcript_adaptor = $otter_dba->get_TranscriptAdaptor;

    my $list_transcripts = $otter_dba->dbc->prepare(q{
        SELECT
                t.transcript_id,
                t.description,
                e.name,
                e.type,
                t.biotype
        FROM
                transcript t
           LEFT JOIN evidence e ON t.transcript_id = e.transcript_id
           JOIN gene g 
             ON t.gene_id = g.gene_id AND g.source = 'havana'
           -- Make sure it is on a writeable seq_region
           JOIN seq_region_attrib sra 
             ON t.seq_region_id = sra.seq_region_id
            AND sra.attrib_type_id = (SELECT attrib_type_id FROM attrib_type WHERE code = 'write_access')
            AND sra.value = 1
        WHERE
                t.is_current = 1
            AND e.type IS NULL
        ORDER BY t.transcript_id
    });
    $list_transcripts->execute;

    my $transcript_attribs = $otter_dba->dbc->prepare(q{
        SELECT
            ta.attrib_type_id,
            at.code,
            ta.value
        FROM
            transcript_attrib ta
            JOIN attrib_type at
              ON ta.attrib_type_id = at.attrib_type_id
             AND at.attrib_type_id IN (
                     SELECT attrib_type_id
                     FROM attrib_type
                     WHERE code IN ('name', 'synonym', 'remark', 'hidden_remark')
             ) 
        WHERE
            transcript_id = ?
        ORDER BY ta.attrib_type_id
    });

    my $str;
    my $io = IO::String->new(\$str);
    my $seqOut = Bio::SeqIO->new(-format => 'Fasta',
                                         -fh     => $io );

    my $count = 0;
    my %bt_count;

    while (my ($tid, $descr, $e_name, $e_type, $biotype) = $list_transcripts->fetchrow()) {
        ++$count;
        ++$bt_count{$biotype};
        printf( "%10d: %s/%s\t[%s] %s\n", 
                $tid, 
                defined($e_name) ? $e_name : 'U', 
                defined($e_type) ? $e_type : 'U', 
                $biotype,
                defined($descr) ? $descr : 'U',
            ) unless $quiet;

        if ($list_attrs and not $quiet) {
            $transcript_attribs->execute($tid);
            while (my ($ati, $code, $value) = $transcript_attribs->fetchrow()) {
                printf( "\t%-15s %s\n", $code, $value);
            }
        }

        if ($dump_seq) {
            my $td = $transcript_adaptor->fetch_by_dbID($tid);
            if ($td) {
                $io->truncate(0);   # reset to start of $str
                $seqOut->write_seq($td->seq);
                print $str;
            }
        }
    }
    if ($biotype_count) {
        printf( "%-40s%-5s\n", "Biotype", "Count");
        printf( "%-40s%-5s\n", "=======", "=====");
        foreach my $key (sort keys %bt_count) {
            printf( "%-40s%5d\n", $key, $bt_count{$key});
        }
        printf "\n" if $total;
    }
    printf "Total: %d\n", $count if $total;

}



__END__

=head1 NAME - list_no_evidence_transcripts.pl

=head1 SYNOPSIS

list_no_evidence_transcripts -dataset <DATASET NAME>

=head1 DESCRIPTION

Checks for current havana transcripts having no entries in the evidence table.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

