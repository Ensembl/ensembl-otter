package Bio::Otter::Utils::Script;

use strict;
use warnings;
use 5.010;

use Carp;

use Bio::Otter::Utils::Script::DataSet;
use Bio::Otter::Server::Config;

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
provides, in addition to the standard options listed FIXME:below.

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

    $self->verbose($opt->{verbose});

    $self->ottscript_validate_args($opt, $args);
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

=cut

sub ottscript_options {
    return;
}

{
    my $_options_hashref;

    sub _options {
        my $class = shift;
        return $_options_hashref ||= {
            dataset_mode => 'only_one',
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

    my $species_dat = Bio::Otter::Server::Config->SpeciesDat;

    my @ds_names = $self->_datasets;
    unless (@ds_names) {
        @ds_names = map { $_->name } @{$species_dat->datasets};
    }

    foreach my $ds_name (sort @ds_names) {
        my $ds = $species_dat->dataset($ds_name);
        unless($ds) {
            $self->_dataset_error("Cannot find dataset '$ds_name'");
            next;
        }
        my $ds_obj = Bio::Otter::Utils::Script::DataSet->new(otter_sd_ds => $ds, script => $self);

        if ($self->verbose) {
            say '-' x 72;
            say "$ds_name";
            say '=' x length($ds_name);
        }

        $self->process_dataset($ds_obj);
    }

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

=cut

sub setup {
    my ($self, $opt, $args) = @_;
    return;
}

=head1 STANDARD OPTIONS

=head2 --dataset

Specify the dataset(s) to be used. See also the C<dataset_mode>
setting to C<ottscript_option> above.

=head2 --help

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
    }

    return (
        @dataset,
        [],
        [ "verbose|v",    "verbose output" ],
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

=head2 verbose

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
