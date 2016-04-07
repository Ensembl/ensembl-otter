#!/usr/bin/env perl

# FIXME: copied from, and lots of duplication with, fix_start_exon_phase_5p.pl

use strict;
use warnings;
use 5.010;

package Bio::Otter::Script::FindDeletedTranscripts;
use parent 'Bio::Otter::Utils::Script';

use Sys::Hostname;
use Try::Tiny;
use POSIX     qw( strftime );

use Hum::Sort qw( ace_sort );
use Bio::Otter::ServerAction::Script::Region;

sub ottscript_options {
    return (
        dataset_mode          => 'only_one', # for now
        dataset_class         => 'Bio::Otter::DataSet::FindDeletedTranscripts',
        transcript_class      => 'Bio::Otter::Transcript::FindDeletedTranscripts',
        allow_iteration_limit => 1,
        allow_modify_limit    => 1,
        );
}

sub process_dataset {
    my ($self, $dataset) = @_;

    my $genes = {};
    $dataset->callback_data('genes' => $genes);

    $dataset->iterate_transcripts( sub { my ($dataset, $ts) = @_; return $self->do_transcript($dataset, $ts); } );

    foreach my $gene ( sort {

        ace_sort($a->[0]->seq_region_name, $b->[0]->seq_region_name)
            ||
            $a->[0]->gene_stable_id  cmp $b->[0]->gene_stable_id

                       } values %$genes ) {

        $self->_process_gene($gene);
    }
    return;
}

sub do_transcript {
    my ($self, $dataset, $lost_ts) = @_;

    my $genes = $dataset->callback_data('genes');
    my $gene_ts = $genes->{$lost_ts->gene_stable_id} //= [];
    push @$gene_ts, $lost_ts;

    my $msg = sprintf('(%-25s) on %18s (%-25s) [%s] - %s',
                      $lost_ts->name,
                      $lost_ts->gene_stable_id,
                      $lost_ts->gene_name,
                      $lost_ts->current_gene ? 'CG' : '--',
                      $lost_ts->seq_region_name,
        );

    return ($msg, undef);  # $msg, $verbose_msg
}

sub _process_gene {
    my ($self, $gene) = @_;

    my @transcripts;
    my %gene_ids;
    foreach my $lost_ts (@$gene) {
        my $ts = $lost_ts->dataset->transcript_adaptor->fetch_latest_by_stable_id($lost_ts->stable_id);
        push @transcripts, $ts;
        $gene_ids{$ts->get_Gene->dbID}++;
    }

    my $spec_ts = $gene->[0];
    say sprintf('%-10s %18s (%-25s) [%s, %s]: %d',
                $spec_ts->seq_region_name,
                $spec_ts->gene_stable_id,
                $spec_ts->gene_name,
                $spec_ts->current_gene ? '1' : '-',
                scalar keys %gene_ids > 1 ? '!!': 'ok',
                scalar(@$gene),
        );
    foreach my $ts (sort { $a->stable_id cmp $b->stable_id } @transcripts) {
        my $ts_gene = $ts->get_Gene;
        my ($ts_name) = @{$ts->get_all_Attributes('name')};
        say sprintf("\t%18s %s %s (%-25s) => %5d %s %s",
                    $ts->stable_id,
                    $ts->is_current,
                    strftime('%F_%T', gmtime $ts->modified_date),
                    $ts_name->value,
                    $ts_gene->dbID,
                    $ts_gene->is_current,
                    strftime('%F_%T', gmtime $ts_gene->modified_date),
            );
    }

    return;
}

# End of module

package Bio::Otter::DataSet::FindDeletedTranscripts;
use Moose;
extends 'Bio::Otter::Utils::Script::DataSet';

sub transcript_sql {
    my $sql = q{
        SELECT DISTINCT
                g1.stable_id        AS gene_stable_id,
                gan.value           AS gene_name,
                t1.stable_id        AS transcript_stable_id,
                t1.seq_region_start AS transcript_start,
                t1.seq_region_end   AS transcript_end,
                tan.value           AS transcript_name,
                sr.name             AS seq_region_name,
                srh.value           AS seq_region_hidden,
                g2.is_current       AS current_gene,
                -1                  AS transcript_id     -- YUK!! perhaps make optional in B:O:U:Script::Transcript?
        FROM
                transcript           t1
           JOIN gene                 g1  ON t1.gene_id = g1.gene_id
           JOIN gene_attrib          gan ON g1.gene_id = gan.gene_id
                                        AND gan.attrib_type_id = (
                                              SELECT attrib_type_id
                                              FROM   attrib_type
                                              WHERE  code = 'name'
                                            )
           JOIN transcript_attrib    tan ON t1.transcript_id = tan.transcript_id
                                        AND tan.attrib_type_id = (
                                              SELECT attrib_type_id
                                              FROM   attrib_type
                                              WHERE  code = 'name'
                                            )
           JOIN seq_region           sr  ON g1.seq_region_id = sr.seq_region_id
           JOIN seq_region_attrib    srh ON sr.seq_region_id = srh.seq_region_id
                                        AND srh.attrib_type_id = (
                                              SELECT attrib_type_id
                                              FROM   attrib_type
                                              WHERE  code = 'hidden'
                                            )
           LEFT JOIN transcript      t2  ON t1.stable_id = t2.stable_id
                                        AND t2.is_current = 1

           LEFT JOIN gene            g2 ON g1.stable_id = g2.stable_id
                                       AND g2.is_current = 1

        WHERE
                t1.is_current    = 0
            AND t2.stable_id     IS NULL

            AND srh.value        = 0            -- not hidden
            AND g1.modified_date > '2015-10-15'

        --  __GROUP_BY__

        ORDER BY seq_region_name, g1.stable_id, t1.stable_id
        __LIMIT__
    };
    return $sql;
};

# End of module

package Bio::Otter::Transcript::FindDeletedTranscripts;
use Moose;
extends 'Bio::Otter::Utils::Script::Transcript';

has 'current_gene'       => ( is => 'ro', required => 1 );

# End of module

package main;

$|++;                           # unbuffer stdout for sane interleaving with stderr
Bio::Otter::Script::FindDeletedTranscripts->import->run;

exit;

# EOF
