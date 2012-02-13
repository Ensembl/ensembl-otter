
package Bio::Otter::UI::TextWindow;

use strict;
use warnings;

use Scalar::Util 'weaken';

sub new {
    my ($pkg, $parent) = @_;

    my $self = bless {}, $pkg;
    $self->parent($parent);

    my $master = $parent->canvas->toplevel;
    my $top = $master->Toplevel;
    $top->transient($master);

    my $window = $top->Scrolled(
        'ROText',
        -scrollbars             => 'e',
        -font                   => $parent->font_fixed,
        -padx                   => 6,
        -pady                   => 6,
        -relief                 => 'groove',
        -background             => 'white',
        -border                 => 2,
        -selectbackground       => 'gold',
        )->pack(
        -expand => 1,
        -fill   => 'both',
        );

    $self->window($window);

    # Frame for buttons
    my $frame = $top->Frame(
        -border => 6,
        )->pack(
        -side   => 'bottom',
        -fill   => 'x',
        );

    $self->buttons($frame, $top);

    return $self;
}

sub parent {
    my ($self, $parent) = @_;
    if ($parent) {
        $self->{'_parent'} = $parent;
        weaken $self->{'_parent'};
    }
    return $self->{'_parent'};
}

sub window {
    my ($self, $window) = @_;
    if ($window) {
        $self->{'_window'} = $window;
    }
    return $self->{'_window'};
}

1;

__END__

=head1 NAME - Bio::Otter::UI::TextWindow

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

