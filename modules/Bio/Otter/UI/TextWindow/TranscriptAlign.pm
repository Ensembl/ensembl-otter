
package Bio::Otter::UI::TextWindow::TranscriptAlign;

use 5.012;

use strict;
use warnings;

use parent 'Bio::Otter::UI::TextWindow';

my $highlight_hydrophobic = 0;

sub new {
    my ($pkg, $parent, $type) = @_;
    my $self = $pkg->SUPER::new($parent);

    $self->type($type);

    return $self;
}

sub buttons {
    my ($self, $frame, $top) = @_;

    # FIXME: likely duplication
    my $close_command = sub{ $top->withdraw; $self->parent->delete_alignment_window($self->type) };

    my $exit = $frame->Button(
        -text => 'Close',
        -command => $close_command ,
        )->pack(-side => 'right');
    $top->bind(    '<Control-w>',      $close_command);
    $top->bind(    '<Control-W>',      $close_command);
    $top->bind(    '<Escape>',         $close_command);

    $self->window->bind('<Destroy>', $close_command);

    $top->protocol('WM_DELETE_WINDOW', $close_command);

    return;
}

sub update_alignment {
    my ($self, $alignment) = @_;
    my $window = $self->window;

    # Empty the text widget
    $window->delete('1.0', 'end');
    $window->insert('end', $alignment); # just show it raw for now

    # FIXME: more duplication (modulo width)
    # Size widget to fit
    my ($lines) = $window->index('end') =~ /(\d+)\./;
    $lines--;
    if ($lines > 40) {
        $window->configure(
            -width  => 80,
            -height => 40,
            );
    } else {
        # This has slightly odd behaviour if the ROText starts off
        # big to accomodate a large translation, and is then made
        # smaller.  Does not seem to shrink below a certain minimum
        # height.
        $window->configure(
            -width  => 80,
            -height => $lines,
            );
    }

    my $toplevel = $window->toplevel;

    # Set the window title
    $toplevel->configure( -title => sprintf("otter: %s alignment", $self->type) );

    $toplevel->deiconify;
    $toplevel->raise;

    return;
}

sub width {
    return 60;
}

sub type {
    my ($self, $type) = @_;
    if ($type) {
        $self->{'_type'} = $type;
    }
    return $self->{'_type'};
}

1;

__END__

=head1 NAME - Bio::Otter::UI::TextWindow::TranscriptAlign

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
