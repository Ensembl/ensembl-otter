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
use Bio::Vega::Author;
use Bio::Vega::SliceLockBroker;
use Bio::Vega::Utils::Attribute qw( add_EnsEMBL_Attributes make_EnsEMBL_Attribute );

use constant RECOVER_PREFIX => '00R_';

use constant RECOVER_COMMENT_FMT     => 'NB!! recovered to %s by find_deleted_transcripts.pl on %s';
use constant RECOVER_COMMENT_PATTERN => qr/recovered to 00R_.+ by find_deleted_transcripts.pl on/;

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

    my $ts_count_stored_gene = 0;
    $dataset->callback_data('ts_store_ref' => \$ts_count_stored_gene);

    my $new_gene_names = {};
    $dataset->callback_data('new_gene_names' => $new_gene_names);
    my $new_ts_names = {};
    $dataset->callback_data('new_ts_names' => $new_ts_names);

    foreach my $gene ( sort {

        ace_sort($a->[0]->seq_region_name, $b->[0]->seq_region_name)
            ||
            $a->[0]->gene_stable_id  cmp $b->[0]->gene_stable_id

                       } values %$genes ) {

        $self->_process_gene($dataset, $gene);
    }
    say "[i] Processed ${ts_count_proc_gene} lost transcripts by gene.";
    say "[i] Stored    ${ts_count_stored_gene} lost transcripts." if $dataset->may_modify;

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
TS: foreach my $lost_ts (@$gene) {

        my $ts_id = $self->_latest_ts_by_stable_id_and_name($dataset, $lost_ts->stable_id, $lost_ts->name);
        my $ts = $dataset->transcript_adaptor->fetch_by_dbID($ts_id);

        if (my $comment = $self->_already_stored($ts)) {
            say sprintf("  skipping %s, already processed on previous run: '%s'", $lost_ts->stable_id, $comment);
            next TS;
        }

        push @transcripts, $ts;

        my $gene = $ts->get_Gene;
        my $by_parent_gene = $parent_gene_ids{$gene->dbID} //= [];
        push @$by_parent_gene, $ts;

        my $gene_name = $self->_get_name($gene);
        $gene_names{$gene_name}++;
    }

    unless (@transcripts) {
        say sprintf("  %18s - all transcripts already processed.\n", $spec_ts->gene_stable_id);
        return;
    }

    say sprintf("  %18s  %s:",
                $spec_ts->gene_stable_id,
                join(', ', sort keys %gene_names),
        );

    my $recover_spec = {
        gene_stable_id => $spec_ts->gene_stable_id,
        gene_remarks   => [],
        genes          => [],
    };

    if ($spec_ts->current_gene) {
        my $current_gene = $dataset->gene_adaptor->fetch_by_stable_id($spec_ts->gene_stable_id);
        my $cg_name = $self->_get_name($current_gene);
        my $name_match = $gene_names{$cg_name};
        say sprintf('    %s There is a current gene with this stable_id %s (gene_id %d, author %s).',
                    $name_match ? '[i]'      : '[W]',
                    $name_match ? "and name" : "BUT DIFFERENT NAME ${cg_name}",
                    $current_gene->dbID,
                    $current_gene->gene_author->name,
            );
        push @{$recover_spec->{gene_remarks}}, sprintf("CURRENT GENE %s (%s)",
                                                       $spec_ts->gene_stable_id,
                                                       $cg_name );
        delete $recover_spec->{gene_stable_id};
    }
    if (scalar keys %parent_gene_ids > 1) {
        say '    [W] Deleted transcripts belong to more than one previous version of this gene';
        delete $recover_spec->{gene_stable_id};
        $recover_spec->{'transcript_name_suffix'}++;
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

GENE: foreach my $gene_id (sort keys %parent_gene_ids) {
        my $gene = $dataset->gene_adaptor->fetch_by_dbID($gene_id);
        say sprintf('     -  Deleted gene_id: %d, modified %s, author %s',
                    $gene_id,
                    $self->_mod_date_time($gene),
                    $gene->gene_author->name,
            );

        if (my $comment = $self->_already_stored($gene)) {
            say sprintf("  skipping, already processed on previous run: '%s'", $comment);
            delete $parent_gene_ids{$gene_id};
            next GENE;
        }

        my $gene_spec = {
            gene       => $gene,
            transcipts => [],
        };

        foreach my $ts (sort { $a->stable_id cmp $b->stable_id } @{$parent_gene_ids{$gene_id}}) {

            ++$$ts_count_ref;

            my $ts_gene = $ts->get_Gene;
            my $ts_name = $self->_get_name($ts);

            my $name_exists = $ctsbn_map{join '/', $ts->stable_id, $ts_name};

            say sprintf('         -  %18s  %-25s - ts_id: %d, modified %s, author %s%s',
                        $ts->stable_id,
                        $ts_name,
                        $ts->dbID,
                        $self->_mod_date_time($ts),
                        $ts->transcript_author->name,
                        $name_exists ? ', NAME EXISTS' : '',
                );

            my $transcript_spec = {
                transcript => $ts,
                remarks    => [],
            };

            my $ts_gene_list = $ts_seen_on->{$ts->stable_id};
            if (scalar @$ts_gene_list > 1) {
                say sprintf('        [W] %18s seen on multiple genes: %s',
                            $ts->stable_id,
                            join(', ', @$ts_gene_list),
                    );
                push @{$transcript_spec->{remarks}}, sprintf("STABLE ID removed, %s existed on genes %s (see report)",
                                                             $ts->stable_id,
                                                             join(', ', @$ts_gene_list) );
                $transcript_spec->{drop_stable_id} = 1;
            }
            push @{$gene_spec->{transcripts}}, $transcript_spec;
        }

        push @{$recover_spec->{genes}}, $gene_spec;
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

    unless (%parent_gene_ids) {
        say '  all parent genes already recovered, no futher action.';
        return;
    }

    say sprintf('    [d] Will rename and recover %s and %s.',
                scalar keys %parent_gene_ids > 1 ? 'these genes' : 'this gene',
                scalar @transcripts > 1          ? 'transcripts' : 'transcript',
        );

    $self->_recover_genes($dataset, $recover_spec);

    say '';
    return;
}

sub _already_stored {
    my ($self, $ens_obj) = @_;

    my $h_remarks = $ens_obj->get_all_Attributes('hidden_remark');
    return unless $h_remarks;

    foreach my $comment (map { $_->value } @$h_remarks) {
        if ($comment =~ RECOVER_COMMENT_PATTERN) {
            return $comment;
        }
    }
    return;
}

sub _recover_genes {
    my ($self, $dataset, $recover_spec) = @_;

    say "\n    RECOVER: ", $recover_spec->{gene_stable_id} || 'gene stable ID discarded';

    my $author = (getpwuid($<))[0];
    my $author_obj;

    if ($dataset->may_modify) {
        $author_obj = Bio::Vega::Author->new(-name => $author, -email => $author);
    }

    my $gene_adaptor   = $dataset->gene_adaptor;
    my $attrib_adaptor = $dataset->otter_dba->get_AttributeAdaptor;

    my $ts_store_ref   = $dataset->callback_data('ts_store_ref');
    my $new_gene_names = $dataset->callback_data('new_gene_names');
    my $new_ts_names   = $dataset->callback_data('new_ts_names');

    foreach my $gene_spec (@{$recover_spec->{genes}}) {
        my $gene = $gene_spec->{gene};

        my $new_gene = $gene->new_dissociated_copy;
        $new_gene->is_current(1);
        $new_gene->stable_id(undef) unless ($recover_spec->{gene_stable_id});
        $new_gene->flush_Transcripts;

        my $gene_comment_attrib =
            $self->_process_attribs($new_gene, $gene, $recover_spec->{gene_remarks}, $new_gene_names);

        my @ts_comment_attribs;

        foreach my $transcript_spec (@{$gene_spec->{transcripts}}) {

            my $transcript = $transcript_spec->{transcript};

            my $new_ts = $transcript->new_dissociated_copy;
            $new_ts->is_current(1);
            $new_ts->stable_id(undef) if $transcript_spec->{drop_stable_id};

            my $ts_comment_attrib =
                $self->_process_attribs($new_ts, $transcript, $transcript_spec->{remarks}, $new_ts_names);
            if ($ts_comment_attrib) {
                push @ts_comment_attribs, { ts => $transcript, comment_attrib => $ts_comment_attrib };
            }

            $new_gene->add_Transcript($new_ts);
            ++$$ts_store_ref;
        }

        # We cannot add 'not for VEGA' until after this:
        $new_gene->set_biotype_status_from_transcripts;

        add_EnsEMBL_Attributes($new_gene, 'remark' => 'not for VEGA');
        foreach my $new_ts (@{$new_gene->get_all_Transcripts}) {
            add_EnsEMBL_Attributes($new_ts, 'remark' => 'not for VEGA');
        }

        # NOW we need to actually store the new gene!
        if ($dataset->may_modify) {
            say '    [d] storing gene:';

            my $broker = Bio::Vega::SliceLockBroker->new
                (-hostname => hostname(), -author => $author_obj, -adaptor => $dataset->otter_dba);

            my $lock_ok;
            my $work = sub {

                $lock_ok = 1;
                $gene_adaptor->store_only($new_gene);

                if ($gene_comment_attrib) {
                    $attrib_adaptor->store_on_Gene($gene, [ $gene_comment_attrib ]);
                }

                foreach my $spec (@ts_comment_attribs) {
                    $attrib_adaptor->store_on_Transcript($spec->{ts}, [ $spec->{comment_attrib} ]);
                }

                say '    -  STORED';
                return;
            };

            try {
                say sprintf('    -  locking gene slice %s <%d-%d>',
                            $gene->seq_region_name,
                            $gene->seq_region_start,
                            $gene->seq_region_end,
                    );
                $broker->lock_create_for_objects('find_deleted_transcripts.pl' => $gene);
                $broker->exclusive_work($work, 1);
            } catch {
                if ($lock_ok) {
                    say "   [E] problem storing gene: '$_'";
                } else {
                    say "   [E] problem locking gene slice with author name $author: '$_'";
                }
            } finally {
                $broker->unlock_all;
                sleep 2;        # avoid overlapping lock expiry issues?
            };

        } else {
            say '    [i] would store new gene here';
        }

        say sprintf('    [i] stored gene: %6d %18s (%s)',
                    $new_gene->dbID // -1,
                    $new_gene->stable_id // 'stable-id-not-set',
                    $self->_get_name($new_gene),
            );
        foreach my $new_ts (@{$new_gene->get_all_Transcripts}) {
            say sprintf('        - stored ts: %6d %18s (%s)',
                        $new_ts->dbID // -1,
                        $new_ts->stable_id // 'stable-id-not-set',
                        $self->_get_name($new_ts),
                );
        }
    }
}

sub _process_attribs {
    my ($self, $new_obj, $old_obj, $remarks, $name_used_cache) = @_;

    delete $new_obj->{attributes};

    add_EnsEMBL_Attributes($new_obj,
                           'hidden_remark' => sprintf('created from dbID %d by find_deleted_transcripts.pl on %s',
                                                      $old_obj->dbID,
                                                      strftime('%F', gmtime),
                           )
        );

    my $new_name;

    foreach my $attrib (@{$old_obj->get_all_Attributes}) {
        if (lc $attrib->code eq 'name') {
            $new_name = RECOVER_PREFIX . $attrib->value;
            if (my $index = $name_used_cache->{$new_name}++) {
                $new_name .= "_$index";
            }
            add_EnsEMBL_Attributes($new_obj, 'name' => $new_name);
        } else {
            $new_obj->add_Attributes($attrib);
        }
    }

    foreach my $remark (@$remarks) {
        add_EnsEMBL_Attributes($new_obj, 'hidden_remark' => $remark);
    }

    my $comment_attrib;
    if ($new_name) {
        my $comment = sprintf(RECOVER_COMMENT_FMT,
                              $new_name,
                              strftime('%F', gmtime));
        $comment_attrib = make_EnsEMBL_Attribute('hidden_remark', $comment);
    }
    return $comment_attrib;
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
