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

my $ts_count;
sub process_dataset {
    my ($self, $dataset) = @_;

    my $genes = {};
    $dataset->callback_data('genes' => $genes);
    my $ts_seen_on = {};
    $dataset->callback_data('ts_seen_on' => $ts_seen_on);

    $dataset->iterate_transcripts( sub { my ($dataset, $ts) = @_; return $self->do_transcript($dataset, $ts); } );
    say "[i] Processed ${ts_count} raw lost transcripts.";

    my $c_sth = $self->_current_ts_by_name_sth($dataset);
    $dataset->callback_data('current_ts_by_name_sth' => $c_sth);
    my $l_sth = $self->_latest_ts_by_stable_id_and_name_sth($dataset);
    $dataset->callback_data('latest_ts_by_stable_id_and_name_sth' => $l_sth);

    my $ts_count_proc_gene = 0;
    $dataset->callback_data('ts_count_ref' => \$ts_count_proc_gene);

    foreach my $gene ( sort {

        ace_sort($a->[0]->seq_region_name, $b->[0]->seq_region_name)
            ||
            $a->[0]->gene_stable_id  cmp $b->[0]->gene_stable_id

                       } values %$genes ) {

        $self->_process_gene($dataset, $gene);
    }
    say "[i] Processed ${ts_count_proc_gene} lost transcripts by gene.";

    return;
}

sub do_transcript {
    my ($self, $dataset, $lost_ts) = @_;

    my $genes = $dataset->callback_data('genes');
    my $gene_ts_list = $genes->{$lost_ts->gene_stable_id} //= [];
    push @$gene_ts_list, $lost_ts;

    my $ts_seen_on = $dataset->callback_data('ts_seen_on');
    my $ts_gene_list = $ts_seen_on->{$lost_ts->stable_id} //= [];
    push @$ts_gene_list, $lost_ts->gene_stable_id;

    my $msg = sprintf('(%-25s) on %18s [%s] - %s',
                      $lost_ts->name,
                      $lost_ts->gene_stable_id,
                      $lost_ts->current_gene ? 'CG' : '--',
                      $lost_ts->seq_region_name,
        );

    ++$ts_count;
    return (undef, $msg);  # $msg, $verbose_msg
}

my $current_sr_name = '';

sub _process_gene {
    my ($self, $dataset, $gene) = @_;

    # new chromosome?
    my $spec_ts = $gene->[0];
    if ((my $sr_name = $spec_ts->seq_region_name) ne $current_sr_name) {
        $current_sr_name = $sr_name;
        say "\n$sr_name:";
    }

    # inflate transcripts to Vega objects, classify on parent gene
    my @transcripts;
    my %parent_gene_ids;
    my %gene_names;
    foreach my $lost_ts (@$gene) {

        my $ts_id = $self->_latest_ts_by_stable_id_and_name($dataset, $lost_ts->stable_id, $lost_ts->name);
        my $ts = $dataset->transcript_adaptor->fetch_by_dbID($ts_id);
        push @transcripts, $ts;

        my $gene = $ts->get_Gene;
        my $by_parent_gene = $parent_gene_ids{$gene->dbID} //= [];
        push @$by_parent_gene, $ts;

        my $gene_name = $self->_get_name($gene);
        $gene_names{$gene_name}++;
    }

    say sprintf("  %18s  %s:",
                $spec_ts->gene_stable_id,
                join(', ', sort keys %gene_names),
        );

    my $current_gene;
    if ($spec_ts->current_gene) {
        $current_gene = $dataset->gene_adaptor->fetch_by_stable_id($spec_ts->gene_stable_id);
        my $cg_name = $self->_get_name($current_gene);
        my $name_match = $gene_names{$cg_name};
        say sprintf('    %s There is a current gene with this stable_id %s (gene_id %d, author %s).',
                    $name_match ? '[i]'      : '[W]',
                    $name_match ? "and name" : "BUT DIFFERENT NAME ${cg_name}",
                    $current_gene->dbID,
                    $current_gene->gene_author->name,
            );
    }
    if (scalar keys %parent_gene_ids > 1) {
        say '    [W] Deleted transcripts belong to more than one previous version of this gene';
    }

    # look for current transcripts with same name as deleted transcript
    my %ctsbn_map;
    foreach my $ts ( @transcripts ) {
        my $ts_name = $self->_get_name($ts);
        my $current_ts_by_name = $self->_current_ts_by_name($dataset, $ts_name);
        $ctsbn_map{join '/', $ts->stable_id, $ts_name} = $current_ts_by_name if $current_ts_by_name;
    }

    my $ts_seen_on   = $dataset->callback_data('ts_seen_on');
    my $ts_count_ref = $dataset->callback_data('ts_count_ref');

    foreach my $gene_id (sort keys %parent_gene_ids) {
        my $gene = $dataset->gene_adaptor->fetch_by_dbID($gene_id);
        say sprintf('     -  Deleted gene_id: %d, modified %s, author %s',
                    $gene_id,
                    $self->_mod_date_time($gene),
                    $gene->gene_author->name,
            );

        foreach my $ts (sort { $a->stable_id cmp $b->stable_id } @{$parent_gene_ids{$gene_id}}) {

            ++$$ts_count_ref;

            my $ts_gene = $ts->get_Gene;
            my $ts_name = $self->_get_name($ts);

            say sprintf('         -  %18s  %-25s - ts_id: %d, modified %s, author %s%s',
                        $ts->stable_id,
                        $ts_name,
                        $ts->dbID,
                        $self->_mod_date_time($ts),
                        $ts->transcript_author->name,
                        $ctsbn_map{join '/', $ts->stable_id, $ts_name} ? ', NAME EXISTS' : '',
                );
            my $ts_gene_list = $ts_seen_on->{$ts->stable_id};
            if (scalar @$ts_gene_list > 1) {
                say sprintf('        [W] %18s seen on multiple genes: %s',
                            $ts->stable_id,
                            join(', ', @$ts_gene_list),
                    );
            }
        }
    }

    if (%ctsbn_map) {
        my %gene_map;
        say '    [W] Current transcripts exist with same name as deleted transcript:';
        foreach my $key (sort keys %ctsbn_map) {
            my $cts_id = $ctsbn_map{$key};
            my $cts = $dataset->transcript_adaptor->fetch_by_dbID($cts_id);
            my ($stable_id, $cts_name) = split '/', $key;
            say sprintf('          %18s  %-25s => %s (%7d), modified %s, author %s',
                        $stable_id,
                        $self->_get_name($cts),
                        $cts->stable_id,
                        $cts_id,
                        $self->_mod_date_time($cts),
                        $cts->transcript_author->name,
                );
            my $cts_gene = $cts->get_Gene;
            $gene_map{$cts_gene->stable_id} = $cts_gene;
        }
        if (scalar keys %gene_map > 1) {
            say '    [W] These current transcripts are on MULTIPLE GENES.';
        }
        foreach my $gene (values %gene_map) {
            say sprintf('%s on %s %-25s (%7d), modified %s, author %s',
                        ' ' x 29,
                        $gene->stable_id,
                        $self->_get_name($gene),
                        $gene->dbID,
                        $self->_mod_date_time($gene),
                        $gene->gene_author->name,
                );
        }
    }

    say sprintf('    [d] Will rename and recover %s and %s.',
                scalar keys %parent_gene_ids > 1 ? 'these genes' : 'this gene',
                scalar @transcripts > 1          ? 'transcripts' : 'transcript',
        );

    say '';
    return;
}

sub _get_name {
    my ($self, $ens_obj) = @_;
    my ($name_attr) = @{$ens_obj->get_all_Attributes('name')};
    return unless $name_attr;
    return $name_attr->value;
}

sub _mod_date_time {
    my ($self, $ens_obj) = @_;
    return strftime('%F_%T', gmtime $ens_obj->modified_date),
}

sub _current_ts_by_name {
    my ($self, $dataset, $name) = @_;
    my $sth = $dataset->callback_data('current_ts_by_name_sth');
    $sth->execute($name);
    my $rows = $sth->fetchall_arrayref({});
    return unless @$rows;
    return $rows->[0]->{transcript_id};
}

sub _current_ts_by_name_sth {
    my ($self, $dataset) = @_;

    my $dbc = $dataset->otter_dba->dbc;
    my $sth = $dbc->prepare(q{
        SELECT
          t.transcript_id as transcript_id
        FROM
               transcript        t
          JOIN transcript_attrib ta  ON t.transcript_id = ta.transcript_id
          JOIN attrib_type       at  ON ta.attrib_type_id = at.attrib_type_id
                                    AND at.code = 'name'
        WHERE
              t.is_current = 1
          AND ta.value     = ?
    });
    return $sth;
}

sub _latest_ts_by_stable_id_and_name {
    my ($self, $dataset, $stable_id, $name) = @_;
    my $sth = $dataset->callback_data('latest_ts_by_stable_id_and_name_sth');
    $sth->execute($stable_id, $name);
    my $rows = $sth->fetchall_arrayref({});
    return unless @$rows;
    return $rows->[0]->{transcript_id};
}

sub _latest_ts_by_stable_id_and_name_sth {
    my ($self, $dataset) = @_;

    my $dbc = $dataset->otter_dba->dbc;
    my $sth = $dbc->prepare(q{
        SELECT
          t.transcript_id as transcript_id
        FROM
               transcript        t
          JOIN transcript_attrib ta  ON t.transcript_id = ta.transcript_id
          JOIN attrib_type       at  ON ta.attrib_type_id = at.attrib_type_id
                                    AND at.code = 'name'
        WHERE
              t.stable_id = ?
          AND ta.value    = ?
        ORDER BY
          t.is_current    DESC,
          t.modified_date DESC,
          t.transcript_id DESC
        LIMIT 1
    });
    return $sth;
}

# End of module

package Bio::Otter::DataSet::FindDeletedTranscripts;
use Moose;
extends 'Bio::Otter::Utils::Script::DataSet';

sub transcript_sql {
    my $sql = q{
        SELECT DISTINCT
                g1.stable_id        AS gene_stable_id,
                t1.stable_id        AS transcript_stable_id,
                tan.value           AS transcript_name,
                sr.name             AS seq_region_name,
                g2.is_current       AS current_gene,
                -1                  AS transcript_id,     -- YUK!! perhaps make these optional in B:O:U:Script::Transcript?
                 1                  AS transcript_start,
                 1                  AS transcript_end,
                'SCRIPT_ERROR'      AS gene_name
        FROM
                transcript           t1
           JOIN gene                 g1  ON t1.gene_id = g1.gene_id
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
            AND g1.is_current    = 0
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
