
### EditWindow::Password

package EditWindow::Password;

use strict;
use warnings;
use Carp;
use base 'EditWindow';

sub initialise {
    my ($self) = @_;

    my $pad = 6;
    my $top = $self->top;
    my $top_frame = $top->Frame(-borderwidth => $pad)->pack( -side => 'top' );

    $top_frame->Label(
        -text   => $self->prompt_string || 'Enter password',
        -anchor => 's',
        )->pack(-side => 'top');

    # Space between label and entry frame
    $top_frame->Frame(
        -height => $pad,
        )->pack(-side => 'top');

    my $entry_frame = $top_frame->Frame->pack( -side => 'top' );
    $self->password_field(
        $entry_frame->Entry(
            -width          => 20,
            -show           => '*',
            -textvariable   => $self->passref,
            )->pack(-side => 'left')
        );

    # Space between password field and button
    $entry_frame->Frame(
        -width => $pad,
        )->pack(-side => 'left');

    my $button = $entry_frame->Button(
        -default    => 'active',
        -text       => 'Send',
        -command    => sub {
            $top->toplevel->Unbusy;
            $top->destroy if Tk::Exists($top);
            },
        )->pack( -side => 'left' );
    $self->submit_button($button);

    my $submit = sub{ $button->focus; $button->invoke };
    $top->bind('<Return>',                  $submit);
    $top->bind('<KP_Enter>',                $submit);
    $top->protocol('WM_DELETE_WINDOW' =>    $submit);

    $entry_frame->bind('<Destroy>', sub { $self = undef });

    $top->withdraw;
    return;
}

sub get_password {
    my ($self) = @_;

    my $pass = '';

    # Check to see if another window has grabbed input
    # (or the user won't be able to type their password
    # into the password field!)
    my $grab_window = $self->top->grabCurrent;
    if ($grab_window) {
        $grab_window->grabRelease;
    }

    $self->top->Popup;
    $self->top->toplevel->Busy;
    $self->password_field->focus;
    $self->set_minsize;     # Does an "update"
    $self->submit_button->waitWindow;

    # Restore input grab to original window
    if ($grab_window) {
        $grab_window->grab;
    }

    return;
}

sub passref {
    my ($self, $passref) = @_;

    if ($passref) {
        $self->{'_passref'} = $passref;
    }
    return $self->{'_passref'};
}

sub prompt_string {
    my ($self, $prompt_string) = @_;

    if ($prompt_string) {
        $self->{'_prompt_string'} = $prompt_string;
    }
    return $self->{'_prompt_string'};
}

sub submit_button {
    my ($self, $submit_button) = @_;

    if ($submit_button) {
        $self->{'_submit_button'} = $submit_button;
    }
    return $self->{'_submit_button'};
}

sub password_field {
    my ($self, $password_field) = @_;

    if ($password_field) {
        $self->{'_password_field'} = $password_field;
    }
    return $self->{'_password_field'};
}

1;

__END__

=head1 NAME - EditWindow::Password

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

