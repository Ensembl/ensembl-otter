#!/usr/bin/env perl
# Copyright [2018-2022] EMBL-European Bioinformatics Institute
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


# Add stable ids to genes and transcripts where missing.

use strict;
use warnings;
use 5.010;

package Bio::Otter::Script::AddMissingStableIds;
use parent 'Bio::Otter::Utils::Script';

use Sys::Hostname;
use Try::Tiny;

use Bio::Vega::Author;
use Bio::Vega::SliceLockBroker;

sub ottscript_options {
    return (
        dataset_mode          => 'only_one', # for now
        dataset_class         => 'Bio::Otter::DataSet::AddMissingStableIds',
        allow_iteration_limit => 1,
        allow_modify_limit    => 1,
        );
}

sub process_dataset {
    my ($self, $dataset) = @_;

    my $g_sth = $self->_update_gene_sth($dataset);
    $dataset->callback_data('update_gene_sth' => $g_sth);
    my $t_sth = $self->_update_transcript_sth($dataset);
    $dataset->callback_data('update_transcript_sth' => $t_sth);

    $dataset->iterate_genes( sub { my ($dataset, $gene) = @_; return $self->do_gene($dataset, $gene); } );

    $dataset->iterate_transcripts( sub { my ($dataset, $ts) = @_; return $self->do_transcript($dataset, $ts); } );

    return;
}

sub do_gene {
    my ($self, $dataset, $script_gene) = @_;
    my $msg = $self->fix_gene($dataset, $script_gene->gene_id);
    return ($msg, $msg);
}

sub do_transcript {
    my ($self, $dataset, $script_ts) = @_;
    my $msg = $script_ts->gene_name;
    $msg .= $self->fix_gene($dataset, $script_ts->gene_id, $script_ts->transcript_id);
    return ($msg, $msg);
}

sub fix_gene {
    my ($self, $dataset, $gene_id, $transcript_id) = @_;

    return '' unless $dataset->may_modify;

    my $msg = "\n    working on gene $gene_id";

    my $gene = $dataset->gene_adaptor->fetch_by_dbID($gene_id);

    my $transcript;
    if ($transcript_id) {
        $transcript = $dataset->transcript_adaptor->fetch_by_dbID($transcript_id);
    }

    my $author = (getpwuid($<))[0];
    my $author_obj = Bio::Vega::Author->new(-name => $author, -email => $author);
    my $lock_broker = Bio::Vega::SliceLockBroker->new
        (-hostname => hostname(), -author => $author_obj, -adaptor => $dataset->otter_dba);

    my $gene_sth       = $dataset->callback_data('update_gene_sth');
    my $transcript_sth = $dataset->callback_data('update_transcript_sth');

    my $lock_ok;
    my $work = sub {

        $lock_ok = 1;

        my $new_gene = $gene->new_dissociated_copy;

        my $anno_broker = $dataset->otter_dba->get_AnnotationBroker;
        $anno_broker->fetch_new_stable_ids_or_prefetch_latest_db_components($new_gene);
        $msg .= "\n    fetched new stable_ids";

        my $changed;
        unless ($gene->stable_id) {
            $gene_sth->execute($new_gene->stable_id, $gene_id);
            $msg .= "\n    SET gene $gene_id stable_id to: " . $new_gene->stable_id;
            $changed++;
        }

        if ($transcript) {
            my $name = $self->_get_name($transcript);
            my $new_ts;
            foreach my $ts (@{$new_gene->get_all_Transcripts}) {
                if ($self->_get_name($ts) eq $name) {
                    $new_ts = $ts;
                    last;
                }
            }
            if ($new_ts) {
                $transcript_sth->execute($new_ts->stable_id, $transcript_id);
                $msg .= "\n    SET transcript $transcript_id stable_id to: " . $new_ts->stable_id;
                $changed++;
            } else {
                $msg .= "\n    [E] cannot find new transcript for '$name'";
            }
        }

        $dataset->inc_modified_count if $changed;
        $msg .= "\n    DONE";

        return;
    };

    try {
        $msg .= sprintf("\n    locking gene slice %s <%d-%d>",
                                $gene->seq_region_name,
                                $gene->seq_region_start,
                                $gene->seq_region_end,
            );
        $lock_broker->lock_create_for_objects('add_missing_stable_ids.pl' => $gene);
        $lock_broker->exclusive_work($work, 1);
    } catch {
        if ($lock_ok) {
            $msg .= "\n    [E] problem storing gene: '$_'";
        } else {
            $msg .= "\n    [E] problem locking gene slice with author name $author: '$_'";
        }
    } finally {
        $lock_broker->unlock_all;
        # sleep 2;        # avoid overlapping lock expiry issues?
    };

    return $msg;
}

sub _get_name {
    my ($self, $ens_obj) = @_;
    my ($name_attr) = @{$ens_obj->get_all_Attributes('name')};
    return unless $name_attr;
    return $name_attr->value;
}

sub _update_gene_sth {
    my ($self, $dataset) = @_;

    my $dbc = $dataset->otter_dba->dbc;
    my $sth = $dbc->prepare(q{
        UPDATE gene
           SET stable_id = ?
         WHERE     gene_id = ?
               AND stable_id IS NULL
         LIMIT 1
    });
    return $sth;
}

sub _update_transcript_sth {
    my ($self, $dataset) = @_;

    my $dbc = $dataset->otter_dba->dbc;
    my $sth = $dbc->prepare(q{
        UPDATE transcript
           SET stable_id = ?
         WHERE     transcript_id = ?
               AND stable_id IS NULL
         LIMIT 1
    });
    return $sth;
}

# End of module

package Bio::Otter::DataSet::AddMissingStableIds;
use Moose;
extends 'Bio::Otter::Utils::Script::DataSet';

around 'gene_sql' => sub {
    my ($orig, $self) = @_;
    my $sql = $self->$orig();
    $sql =~ s/__EXTRA_CONDITIONS__/
              AND g.stable_id IS NULL /;
   return $sql;
};

around 'transcript_sql' => sub {
    my ($orig, $self) = @_;
    my $sql = $self->$orig();
    $sql =~ s/__EXTRA_CONDITIONS__/
              AND t.stable_id IS NULL /;
   return $sql;
};

# End of module

package main;

$|++;                           # unbuffer stdout for sane interleaving with stderr
Bio::Otter::Script::AddMissingStableIds->import->run;

exit;

# EOF
