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


use strict;
use warnings;
use 5.010;

package Bio::Otter::Script::FixSharedExonStableIDs;
use parent 'Bio::Otter::Utils::Script';

use Carp;

use Bio::Otter::ServerAction::Script::Region;

sub ottscript_options {
    return (
        dataset_mode          => 'only_one', # for now
        allow_modify_limit    => 1,
        );
}

sub process_dataset {
  my ($self, $dataset) = @_;

  my $check_sth = $dataset->otter_dba->dbc->prepare($self->_check_sql);
  my $fix_sth   = $dataset->otter_dba->dbc->prepare($self->_fix_sql);

  my $exon_sth = $dataset->otter_dba->dbc->prepare($self->_exon_sql);
  $exon_sth->execute;

  my %seen;
  my $count = 0;

  while (my $cols = $exon_sth->fetchrow_hashref) {

      my (%e1, %e2);
      my @e_keys = qw ( exon_id stable_id sr_name t_current g_current );
      ( @e1{@e_keys},
        @e2{@e_keys} )
          = @{$cols}{ qw( exon_id_1 exon_stable_id_1 sr_name_1 t1_current g1_current
                          exon_id_2 exon_stable_id_2 sr_name_2 t2_current g2_current ) };

      my $pair = "$e1{stable_id} [$e1{sr_name}] <=> $e2{stable_id} [$e2{sr_name}]";
      if ($seen{$e2{exon_id}}++) {
          say "Already seen: $e2{stable_id} [$e2{sr_name}]" if $dataset->verbose;
          next;
      }
      if ($e2{t2_current} or $e2{g2_current}) {
          say "BOTH CURRENT: $pair";
          next;
      }

      $check_sth->execute($e2{exon_id});
      my ($et_count) = $check_sth->fetchrow_array;
      if ($et_count) {
          say "E2 HAS ACTIVE INVOLVEMENTS: $pair ($et_count)";
          # Optimisation: E1 will crop up as E2 if it hasn't already
          $seen{$e1{exon_id}}++;
          next;
      }

      say "$pair:";
      if ($dataset->may_modify) {
          my $n_updated = $fix_sth->execute($e2{exon_id});
          unless ($n_updated == 1) {
              my $errstr = $fix_sth->errstr;
              croak "Expected to update 1 row, but updated $n_updated [$errstr]";
          }
          say "\t$e2{stable_id} [$e2{sr_name}] is_current CLEARED";
          $dataset->inc_modified_count;
      } else {
          say "\t$e2{stable_id} [$e2{sr_name}] would clear is_current";
      }

      $count++;
  }

  say "Modified ", $dataset->modified_count, " of $count modifiable pairs.";
  return;
}

sub _exon_sql {
    my ($self) = @_;
    my $sql = q{

      select
        e1.exon_id    as exon_id_1,
        e1.stable_id  as exon_stable_id_1,
        sr1.name      as sr_name_1,
        t1.is_current as t1_current,
        g1.is_current as g1_current,

        e2.exon_id    as exon_id_2,
        e2.stable_id  as exon_stable_id_2,
        sr2.name      as sr_name_2,
        t2.is_current as t2_current,
        g2.is_current as g2_current

      from
             exon            e1
        join exon            e2  on (e1.stable_id = e2.stable_id)

        join seq_region      sr1 on (e1.seq_region_id = sr1.seq_region_id)
        join exon_transcript et1 on (e1.exon_id = et1.exon_id)
        join transcript      t1  on (et1.transcript_id = t1.transcript_id)
        join gene            g1  on (t1.gene_id = g1.gene_id)

        join seq_region      sr2 on (e2.seq_region_id = sr2.seq_region_id)
        join exon_transcript et2 on (e2.exon_id = et2.exon_id)
        join transcript      t2  on (et2.transcript_id = t2.transcript_id)
        join gene            g2  on (t2.gene_id = g2.gene_id)

      where
            e1.exon_id       != e2.exon_id
        and e1.seq_region_id != e2.seq_region_id

        and e1.is_current = 1
        and e2.is_current = 1

        and (t1.is_current = 1 and g1.is_current = 1)

       group by e1.exon_id, e2.exon_id, g1.gene_id, g2.gene_id

    };
    return $sql;
}

sub _check_sql {
    my ($self) = @_;
    my $sql = q{
      select count(*)
        from
               exon_transcript et
          join transcript      t  on (et.transcript_id = t.transcript_id)
          join gene            g  on (t.gene_id = g.gene_id)
        where
              et.exon_id = ?
          and (t.is_current = 1 and g.is_current = 1)
    };
    return $sql;
}

sub _fix_sql {
    my ($self) = @_;
    my $sql = q{
      update exon
          set is_current = 0
        where exon_id = ?
        limit 1
    };
    return $sql;
}

# End of module

package main;

$|++;                           # unbuffer stdout for sane interleaving with stderr
Bio::Otter::Script::FixSharedExonStableIDs->import->run;

exit;

# EOF
