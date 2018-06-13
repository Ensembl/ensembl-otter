#!/usr/bin/env perl
# Copyright [2018] EMBL-European Bioinformatics Institute
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


package Bio::Otter::Script::RationaliseStartEndNFAttrs;

use strict;
use warnings;
use 5.010;

use Carp;

use parent 'Bio::Otter::Utils::Script';

sub ottscript_options {
    return (
        dataset_mode          => 'only_one', # for now
        allow_iteration_limit => 1,
        allow_modify_limit    => 1,
        );
}

sub process_dataset {
  my ($self, $dataset) = @_;

  my $find_sth = $self->find_attrs_sth($dataset);
  $dataset->callback_data('find_attrs_sth' => $find_sth);
  my $delete_sth = $self->delete_attr_sth($dataset);
  $dataset->callback_data('delete_attr_sth' => $delete_sth);

  $dataset->iterate_transcripts(\&do_transcript);

  return;
}

sub do_transcript {
    my ($dataset, $ts) = @_;

    my $verbose = $dataset->verbose;

    my $find_sth   = $dataset->callback_data('find_attrs_sth');
    my $delete_sth = $dataset->callback_data('delete_attr_sth');

    $find_sth->execute($ts->transcript_id);
    my $rows = $find_sth->fetchall_arrayref({});

    my $msg;
    my $verbose_msg;

    if (@$rows) {
        my $n = scalar(@$rows);
        my $d = 0;
        foreach my $row ( @$rows ) {
            my $v_id;
            $v_id = sprintf(
               "%s=%s (%d, %d)", $row->{code}, $row->{value}, $row->{transcript_id}, $row->{attrib_type_id}
                ) if $verbose;
            if ($dataset->may_modify) {
                my $n_deleted = $delete_sth->execute($row->{transcript_id}, $row->{attrib_type_id});
                if ($n_deleted == 1) {
                    $d += $n_deleted;
                    $verbose_msg .= "\n\t$v_id DELETED" if $verbose;
                } else {
                    my $errstr = $delete_sth->errstr;
                    croak "Expected to delete 1 row, but deleted $n_deleted [$errstr]";
                }
            } else {
                $verbose_msg .= "\n\t$v_id would be deleted" if $verbose;
            }
        }
        $msg = $dataset->may_modify ? "DELETED $d of $n attributes" : "would delete $n attributes";
        $dataset->inc_modified_count if $d;
    } else {
        $verbose_msg = 'ok';
    }
    return ($msg, $verbose_msg);
}

sub find_attrs_sth {
    my ($self, $dataset) = @_;

    my $dbc = $dataset->otter_dba->dbc;
    my $sth = $dbc->prepare(q{
        SELECT
          ta.transcript_id  as transcript_id,
          ta.attrib_type_id as attrib_type_id,
          at.code           as code,
          ta.value          as value
        FROM
               transcript        t
          JOIN transcript_attrib ta ON t.transcript_id = ta.transcript_id
          JOIN attrib_type       at ON ta.attrib_type_id = at.attrib_type_id
        WHERE
              t.transcript_id = ?
          AND ta.value        = 0
          AND at.code IN (
            'mRNA_start_NF',
            'mRNA_end_NF',
            'cds_start_NF',
            'cds_end_NF'
          )
    });
    return $sth;
}

sub delete_attr_sth {
    my ($self, $dataset) = @_;

    my $dbc = $dataset->otter_dba->dbc;
    my $sth = $dbc->prepare(q{
        DELETE FROM transcript_attrib
        WHERE transcript_id  = ?
        AND   attrib_type_id = ?
        AND   value          = 0
        LIMIT 1
    });
    return $sth;
}

# End of module

package main;

Bio::Otter::Script::RationaliseStartEndNFAttrs->import->run;

exit;

# EOF
