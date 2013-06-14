package Bio::Otter::Script::ListFooBars;

use strict;
use warnings;
use 5.010;

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
        dataset_mode => 'one_or_all',
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

package main;

Bio::Otter::Script::ListFooBars->import->run;

exit;

# EOF
