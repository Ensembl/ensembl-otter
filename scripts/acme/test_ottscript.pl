#!/usr/bin/env perl
# Copyright [2018-2020] EMBL-European Bioinformatics Institute
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

package Bio::Otter::Script::ListFooBars;
use parent 'Bio::Otter::Utils::Script';

sub ottscript_opt_spec {
  return (
    [ "foo-bar-pattern|p=s", "select foo-bars matching pattern", { default => '.*' } ],
  );
}

sub ottscript_validate_args {
  my ($self, $opt, $args) = @_;

  # no args allowed, only options!
  $self->usage_error("No args allowed") if @$args;
  return;
}

sub ottscript_options {
    return (
        dataset_mode  => 'one_or_all',
        dataset_class => 'Bio::Otter::DataSet::ListFooBars',
        );
}

sub process_dataset {
  my ($self, $dataset) = @_;
  my $ds_name = $dataset->name;
  $dataset->iterate_transcripts(
      sub {
          my ($self, $ts) = @_;
          my $ts_name   = $ts->name;
          my $sr_name   = $ts->seq_region_name;
          my $sr_hidden = $ts->seq_region_hidden;
          say "\t'$ds_name': '$ts_name' on '$sr_name' ($sr_hidden)";
          return;
      }
      );
  return;
}

# End of module

package Bio::Otter::DataSet::ListFooBars;
use Moose;
extends 'Bio::Otter::Utils::Script::DataSet';

around 'transcript_sql' => sub {
    my ($orig, $self) = @_;
    my $sql = $self->$orig;
    $sql =~ s/__EXTRA_CONDITIONS__/AND tan.value LIKE 'A%'/;
    return $sql;
};

1;

# End of module

package main;

Bio::Otter::Script::ListFooBars->import->run;

exit;

# EOF
