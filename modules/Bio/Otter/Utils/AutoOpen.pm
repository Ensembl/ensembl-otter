package Bio::Otter::Utils::AutoOpen;
use strict;
use warnings;
use Try::Tiny;


=head1 NAME

Bio::Otter::Utils::AutoOpen - helper to get a window opened "automatically"

=head1 DESCRIPTION

Consstructing the object starts the process, and it hooks itself onto
an after callback.  The object will forget itself when the work is
complete.  If it fails, the error will go to the MainLoop handler.

There isn't much public API, because the internals should be expected
to change with the GUI.

=cut

sub new {
    my ($pkg, $SpeciesListWindow, $openspec) = @_;
    my $self = { _SLW => $SpeciesListWindow, open => $openspec };
    bless $self, $pkg;
    $self->_init;
    return $self;
}

sub _SLW {
    my ($self) = @_;
    return $self->{_SLW};
}

sub _more_work {
    my ($self) = @_;
    return @{ $self->{_work} } ? 1 : 0;
}

sub _take_work {
    my ($self) = @_;
    return shift @{ $self->{_work} };
}

sub _init {
    my ($self) = @_;
    my @work;
    $self->{_work} = \@work;

    my ($ds, $seq_region, $pos) = split '/', $self->{open}, 3;
    # later, should take a 4th part to specify ColumnChooser options

    die "Open shortcut syntax: --open dataset[:seq_region]\n" unless $ds;
    push @work, [ open_dataset_by_name => $ds ];
    push @work, [ open_sequenceseq_by_name => $seq_region ] if defined $seq_region;

    if (defined $pos && $pos =~ m{^(\d[0-9_]*):(\d[0-9_]*)$}) {
        push @work, [ open_region_by_coords => (0+$1), (0+$2) ];
    } elsif (defined $pos && $pos =~ m{^#(\d+)\.\.(\d+)$}) {
        push @work, [ open_region_by_index => $1, $2 ];
    } elsif (defined $pos) {
        push @work, [ open_region_by_hunt => $pos ];
    }

    return $self->_hook;
}

sub _hook {
    my ($self) = @_;
    $self->_SLW->top_window->afterIdle([ $self, 'do_open' ])
      if $self->_more_work;
    return;
}

sub do_open {
    my ($self) = @_;

    my $next = $self->_take_work;
    my ($method, @arg) = @$next;
    die "Don't know how to ($method, @arg) yet" unless $self->can($method);
    $self->$method(@arg);

    return $self->_hook;
}

# --open human_dev
sub open_dataset_by_name {
    my ($self, $ds) = @_;
    $self->_SLW->top_window->iconify;
    my $ssc = $self->_SLW->open_dataset_by_name($ds);
    $self->{ssc} = $ssc; # a CanvasWindow::SequenceSetChooser
    $ssc->top_window->iconify if $self->_more_work;
    return;
}

# --open human_dev/chr12-38
sub open_sequenceseq_by_name {
    my ($self, $seq_region) = @_;
    my $ssc = $self->{ssc}
      or die "Cannot open_sequenceseq_by_name without a CanvasWindow::SequenceSetChooser";

    my $sn = $ssc->open_sequence_set_by_ssname_subset($seq_region, undef);
    $self->{sn} = $sn; # a CanvasWindow::SequenceNotes
    $sn->top_window->iconify if $self->_more_work;
    return;
}


1;
