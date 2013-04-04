
### EditWindow

package EditWindow;

use strict;
use warnings;

use Try::Tiny;
use Scalar::Util 'weaken';

sub new {
    my ($pkg, $tk) = @_;

    my $self = bless {}, $pkg;
    $self->top($tk);
    return $self;
}

sub show_for_parent {
    my ($pkg, $obj_ref, %opt) = @_;
    my $wait_close = delete $opt{wait};

    if (!$$obj_ref) {
        $$obj_ref = $pkg->_create_for_parent(%opt);
        weaken($$obj_ref);
    }
    my $self = $$obj_ref;
    $self->top->deiconify;
    $self->top->raise;

    $self->top->waitWindow if $wait_close;

    return $self;
}

sub _create_for_parent {
    my ($pkg, %opt) = @_;

    my $title = delete $opt{title};
    $title = $pkg unless defined $title;
    $title = $Bio::Otter::Lace::Client::PFX.$title;

    my $parent = delete $opt{from};
    my $top = $parent->Toplevel(-title => $title);
    $top->transient($parent) if delete $opt{transient};

    my $self = $pkg->new($top);

    # set linkages
    while (my ($method, $val) = each %{ delete $opt{linkage} || {} }) {
        $self->$method($val);
    }

    # escape hatch!
    (delete $opt{pre_init})->($self) if ref($opt{pre_init});

    $self->initialise;

    my @left = sort keys %opt;
    warn "Unrecognised options (@left) left after $pkg->_create_for_parent"
      if @left;

    return $self;
}

sub top {
    my ($self, $top) = @_;

    if ($top) {
        $self->{'_top'} = $top;
    }
    return $self->{'_top'};
}

sub balloon {
    my ($self) = @_;

    $self->{'_balloon'} ||= $self->top->Balloon(
        -state  => 'balloon',
        );
    return $self->{'_balloon'};
}

sub set_minsize {
    my ($self) = @_;

    my $top = $self->top;
    $top->update;
    $top->minsize($top->width, $top->height);
    return;
}

sub get_clipboard_text {
    my ($self) = @_;

    my $top = $self->top;
    return unless Tk::Exists($top);

    return try {
        return $top->SelectionGet(
            -selection => 'PRIMARY',
            -type      => 'STRING',
            );
    };
}

1;

__END__

=head1 NAME - EditWindow

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

