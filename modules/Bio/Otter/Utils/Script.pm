=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Bio::Otter::Utils::Script;

use strict;
use warnings;
use 5.010;

use Carp;

use Bio::Otter::Server::Config;
use Bio::Otter::Utils::RequireModule qw(require_module);

use parent 'App::Cmd::Simple';

=head1 NAME

Bio::Otter::Utils::Script - boilerplate for scripts

=head1 DESCRIPTION

Provide framework, boilerplate and support for Otter/Loutre
scripts.

=head1 SYNOPSIS

In F<list_foobars.pl>:

  package Bio::Otter::Script::ListFooBars;
  use parent 'Bio::Otter::Utils::Script';

  sub ottscript_opt_spec {
    return (
      [ "foo-bar-pattern|p=s", "select foo-bars matching pattern" ],
    );
  }

  sub ottscript_validate_args {
    my ($self, $opt, $args) = @_;

    # no args allowed, only options!
    $self->usage_error("No args allowed") if @$args;
  }

  sub process_dataset {
    my ($self, $dataset) = @_;
    # Do useful stuff to $dataset
  }

  package main;

  Bio::Otter::Script::ListFooBars->import->run;

=head1 SUBCLASSING AND CLASS METHODS

=head2 ottscript_opt_spec

This method should be overridden to specify the options this command
provides, in addition to the standard options (see L</STANDARD
OPTIONS> below).

See L<App::Cmd::Simple/opt_spec> and L<Getopt::Long::Descriptive>
for full details.

=cut

sub ottscript_opt_spec {
    return;
}

sub opt_spec {
    my $class = shift;
    return (
        $class->ottscript_opt_spec,
        $class->_standard_opt_spec,
        );
}

=head2 ottscript_validate_args

  $cmd->ottscript_validate_args(\%opt, \@args);

This method may be overridden to perform checks on the processed command
line options and arguments. It is called after the standard options have
been checked. It should throw an exception by calling C<usage_error> if
checks fail, or else simply C<return> if all is okay.

Note that ottscript_validate_args should shift anything it processes off
\@args, as any left-overs will be treated as an arguments error.

=cut

sub ottscript_validate_args {
    return;
}

sub validate_args {
    my ($self, $opt, $args) = @_;
    die "Usage: " . $self->usage if $opt->{help};

    my @datasets;
    my $ds_opts = $opt->{dataset};
    if ($ds_opts) {
        @datasets = ref($ds_opts) ? @$ds_opts : $ds_opts;
    }
    @datasets = map { split ',' } @datasets if @datasets;
    for ( $self->_option('dataset_mode') ) {
        if ( /^only_one$/ or /^multi$/ ) {
            $self->usage_error("Dataset required") unless scalar(@datasets);
            # Otherwise drop through...
        }
        if ( /^one_or_all$/ ) {
            last if scalar(@datasets) == 0;
            # Otherwise drop through...
        }
        if ( /^only_one$/ or /^one_or_all$/ ) {
            last if scalar(@datasets) == 1;
            $self->usage_error("Exactly one dataset must be specified");
        }
    }
    $self->_datasets(@datasets);

    if (my $sso = $self->_option('sequence_set')) {
        for ( $sso ) {
            if ( /^required$/ ) {
                $self->usage_error("sequence-set must be specified") unless $opt->{sequence_set};
                last;
            }
            unless ( /^optional$/ ) {
                croak "Don't understand sequence_set mode '$_'";
            }
        }
        $self->sequence_set_name($opt->{sequence_set});
    }

    foreach my $option (qw{ dry_run limit modify_limit verbose }) {
        $self->$option($opt->{$option});
    }

    $self->ottscript_validate_args($opt, $args);

    if (@$args) {
        my $unexpected = join ' ', @$args;
        $self->usage_error("Unexpected arguments: '$unexpected'");
    }

    return;
}

=head2 ottscript_options

Sets options for L<Bio::Otter::Utils::Script> processing.

=head3 dataset_mode

=over

=item none

No dataset processing. In this case C<execute> must be overridden by the
script.

=item only_one

A single dataset. (DEFAULT)

=item one_or_all

A single dataset, if specified. Otherwise all datasets.

=item multi

One or more datasets, which can be specified by multiple C<--dataset>
options or separated by commas.

=back

=head3 allow_iteration_limit

Enables the C<--limit> option, which should be used to limit the total
number of iterations performed by the script.

Used by L<Bio::Utils::Script::DataSet/iterate_transcripts>.

=head3 allow_modify_limit

Enables the C<--modify-limit> option, which should be used to limit
the number of modifications made before reverting to dry-run
processing.

See L</inc_modified_count> and L</may_modify> methods for supporting
infrastructure.

=head3 no_aliases

If set, when L<Bio:Otter::Utils::Script> iterates over all databases,
it will skip species which are aliases for others (i.e. test and dev
species).

=cut

sub ottscript_options {
    return;
}

{
    my $_options_hashref;

    sub _options {
        my $class = shift;
        return $_options_hashref ||= {
            dataset_mode     => 'only_one',
            dataset_class    => 'Bio::Otter::Utils::Script::DataSet',
            gene_class       => 'Bio::Otter::Utils::Script::Gene',
            transcript_class => 'Bio::Otter::Utils::Script::Transcript',
            $class->ottscript_options,
        };
    }

    sub _option {
        my ($class, $key) = @_;
        return $class->_options->{$key};
    }
}

=head2 execute

Only required if dataset_mode is 'none'.

(The provided default calls process_dataset() for each dataset in turn.)

=cut

sub execute {
    my ($self, $opt, $args) = @_;

    if ($self->_option('dataset_mode') eq 'none') {
        my $class = ref $self;
        croak("execute() should be implemented by $class when dataset_mode is 'none'");
    }

    $self->setup_data($self->setup($opt, $args));

    my $dataset_class = $self->_option('dataset_class');
    require_module($dataset_class, no_die => 1);
    # if that failed, we assume that the dataset class is provided in the script file

    my $species_dat = Bio::Otter::Server::Config->SpeciesDat;

    my @ds_names = $self->_datasets;
    unless (@ds_names) {
        my @datasets = $self->_option('no_aliases') ? $species_dat->all_datasets_no_alias : $species_dat->all_datasets;
        @ds_names = map { $_->name } @datasets;
    }

    foreach my $ds_name (sort @ds_names) {
        my $ds = $species_dat->dataset($ds_name);
        unless($ds) {
            $self->_dataset_error("Cannot find dataset '$ds_name'");
            next;
        }
        my $ds_obj = $dataset_class->new(otter_sd_ds => $ds, script => $self);
        my $ss_obj;
        if (my $ss_name = $self->sequence_set_name) {
            my $ssa = $ds_obj->otter_dba->get_SliceAdaptor;
            $ss_obj = $ssa->fetch_by_region('chromosome', $ss_name);
            unless ($ss_obj) {
                $self->_dataset_error("Cannot retrieve sequence_set '$ss_name' for dataset '$ds_name'");
                next;
            }
        }

        if ($self->verbose) {
            say '-' x 72;
            say "$ds_name";
            say '=' x length($ds_name);
        }

        $self->process_dataset($ds_obj, $ss_obj);
    }

    $self->finish;

    return;
}

{
    my @_datasets;

    sub _datasets {
        my ($self, @args) = @_;
        @_datasets = @args if @args;
        return @_datasets;
    }
}

sub _dataset_error {
    my ($self, $error) = @_;
    if ($self->_option('dataset_mode') eq 'multi') {
        warn "$error - skipping";
    } else {
        die $error;
    }
    return;
}

=head2 process_dataset

  $cmd->process_dataset($dataset);

Must be provided unless C<dataset_mode> option is 'none'.

Called with a dataset object for each dataset in turn.  The dataset
object is an enhanced L<Bio::Otter::SpeciesDat::DataSet>, which
provides useful iterators. Script methods are available via
C<$dataset->script>.

For most scripts C<process_dataset> will be the primary action method.

=head2 setup

  $setup_data = $cmd->setup($opt, $args);

May be overridden to perform one-off setup for the script, before
processing datasets. If a value is returned, it will be stored and
made available via C<setup_data> (which can be accessed within each
invocation of C<process_dataset> via C<$dataset->script->setup_data>).

Will not be called automatically if C<dataset_mode> option is 'none'.

=cut

sub setup {
    my ($self, $opt, $args) = @_;
    return;
}

=head2 finish

  $cmd->finish();

May be overridden to perform final actions after processing datasets.

Will not be called automatically if C<dataset_mode> option is 'none'.

=cut

sub finish {
    my ($self, $opt, $args) = @_;
    return;
}

=head1 STANDARD OPTIONS

=head2 --dataset

Specify the dataset(s) to be used. See also the C<dataset_mode>
setting to C<ottscript_option> above.

=head2 --verbose | -v

Produce verbose output. Available via the L</verbose> method.

=head2 --limit | -l

Limit total number of iterations. See L</allow_iteration_limit>
ottscript_option. Available via the L</limit> method.

=head2 --modify-limit | -m

Limit number of modifications to be made. See L</allow_modify_limit>
ottscript_option.

=head2 --dry-run | -n

Do not make any modifications. Available via the L</dry_run> method.

=head2 --help | -h

Produce the usage message. This is assembled automatically from
C<ottscript_opt_spec>.

=cut

sub _standard_opt_spec {
    my $class = shift;

    my $dataset_spec;
    for ( $class->_option('dataset_mode') ) {
        if ( /^none$/ )                       { last; }
        if ( /^only_one$/ or /^one_or_all$/ ) { $dataset_spec = 's';  last; }
        if ( /^multi$/ )                      { $dataset_spec = 's@'; last; }
        croak("Don't understand dataset_mode '$_'");
    }
    my @dataset;
    if ($dataset_spec) {
        push @dataset, [ "dataset=${dataset_spec}",    "dataset name" ];
        push @dataset, [ "sequence-set|set|chr=s",     "sequence set or chromosome name" ]
            if $class->_option('sequence_set');
    }

    my @limits;
    push @limits, [ "limit|l=i",        "limit number of iterations" ]    if $class->_option('allow_iteration_limit');
    push @limits, [ "modify-limit|m=i", "limit number of modifications" ] if $class->_option('allow_modify_limit');

    return (
        @dataset,
        [],
        [ "verbose|v",    "verbose output" ],
        [ "dry-run|n",    "dry run - no changes made" ],
        @limits,
        [ "help|usage|h", "show usage" ],
        );
}

=head1 OTHER METHODS

=head2 setup_data

Returns the data provided by the C<setup> method, if anything was
returned.

=cut

sub setup_data {
    my ($self, @args) = @_;
    ($self->{'setup_data'}) = @args if @args;
    my $setup_data = $self->{'setup_data'};
    return $setup_data;
}

=head2 sequence_set_name

Returns the sequence set name set by the C<--sequence-set> option, if
enabled.

=cut

sub sequence_set_name {
    my ($self, @args) = @_;
    ($self->{'sequence_set_name'}) = @args if @args;
    my $sequence_set_name = $self->{'sequence_set_name'};
    return $sequence_set_name;
}

=head2 dry_run

Returns true if L</--dry-run> option has been given.

=cut

sub dry_run {
    my ($self, @args) = @_;
    ($self->{'dry_run'}) = @args if @args;
    my $dry_run = $self->{'dry_run'};
    return $dry_run;
}

=head2 limit

Returns the limit set by the C<--limit> option, if enabled.

=cut

sub limit {
    my ($self, @args) = @_;
    ($self->{'limit'}) = @args if @args;
    my $limit = $self->{'limit'};
    return $limit;
}

=head2 modify_limit

Returns the limit set by the C<--modify-limit> option, if enabled.

=cut

sub modify_limit {
    my ($self, @args) = @_;
    ($self->{'modify_limit'}) = @args if @args;
    my $modify_limit = $self->{'modify_limit'};
    return $modify_limit;
}

=head2 inc_modified_count

Increment the internal script counter of the number of modifications
made. See L</may_modify> below.

=cut

sub inc_modified_count {
    my ($self, $inc) = @_;
    $inc ||= 1;
    return $self->modified_count($self->modified_count + $inc);
}

sub modified_count {
    my ($self, @args) = @_;
    ($self->{'modified_count'}) = @args if @args;
    my $modified_count = $self->{'modified_count'} || 0;
    return $modified_count;
}

=head2 may_modify

Returns true unless the L</--dry-run> option has been specified, or
else unless the number of modifications made exceeds the limit set by
the L</--modify-limit> option if specified.

=cut

sub may_modify {
    my $self = shift;
    return if $self->dry_run;            # never allow if dry_run, otherwise...
    return 1 unless $self->modify_limit; # always allow if no modify_limit...
    return ($self->modified_count < $self->modify_limit);
}

=head2 verbose

Returns true if L</--verbose> option has been given.

=cut

sub verbose {
    my ($self, @args) = @_;
    ($self->{'verbose'}) = @args if @args;
    my $verbose = $self->{'verbose'};
    return $verbose;
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
