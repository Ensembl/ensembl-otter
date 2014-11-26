
### EditWindow::Password

package EditWindow::Password;

use strict;
use warnings;
use Carp;
use base 'EditWindow';

use Bio::Otter::Log::Log4perl 'logger';

sub client {
    my ($self, @set) = @_;
    my ($client) = @set ? @set : ($self->{client});

    if (@set) {
        ($self->{client}) = @set;

        my $prompt_sub = sub { return $self->_prompt_sub(@_) };
        my $passwarn_sub = sub { return $self->_passwarn_sub(@_) };

        $client->password_prompt($prompt_sub);
        $client->password_problem($passwarn_sub);

        my $user = $client->author;
        $self->prompt_string("Enter web password for '$user'");
    }

    return $client;
}

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

    my $submit = [ $self, 'Done', 'send' ];
    my $abort  = [ $self, 'Done', 'abort' ];
    my $button = $entry_frame->Button(
        -default    => 'active',
        -text       => 'Send',
        -command    => $submit,
        )->pack( -side => 'left' );
    $self->submit_button($button);

    $top->bind('<Return>',                  $submit);
    $top->bind('<KP_Enter>',                $submit);
    $top->protocol('WM_DELETE_WINDOW' =>    $abort);

    $entry_frame->bind('<Destroy>', sub { $self = undef });

    $top->withdraw;
    return;
}

sub Done {
    my ($self, $val) = @_;
    my $top = $self->top;
    $self->forget if $val eq 'abort';
    if (Tk::Exists($top)) {
        ${ $self->finref } = "done:$val";
        $top->toplevel->Unbusy;
        $top->withdraw;
    }
    return;
}

sub get_password {
    my ($self) = @_;
    my $finref = $self->finref;

    if ($self->{showing}) {
        $self->Done('abort');
        confess "Re-entrant password request, rejecting both";
    }
    local $self->{showing} = 1;

    # Check to see if another window has grabbed input
    # (or the user won't be able to type their password
    # into the password field!)
    my $grab_window = $self->top->grabCurrent;
    if ($grab_window) {
        $grab_window->grabRelease;
    }

    $self->top->deiconify;
    $self->top->raise;

    $self->top->Popup;
    $self->top->toplevel->Busy;
    $self->password_field->focus;
    $self->set_minsize;     # Does an "update"

    $$finref = '';
    $self->logger->info("get_password: prewait (${$self->finref})");
    $self->top->waitVariable($self->finref);
    $self->logger->info("get_password: postwait (${$self->finref})");

    # Restore input grab to original window
    if ($grab_window) {
        $grab_window->grab;
    }

    my $out = ${ $self->passref };
    $self->forget;

    return $out;
}

sub forget {
    my ($self) = @_;
    my $passref = $self->passref;
    my $l = defined $$passref ? length($$passref) : 0;
    substr($$passref, 0, $l) = '*' x $l if $l;
    $$passref = undef;
    return;
}

sub passref {
    my ($self) = @_;
    return ($self->{'_passref'} ||= do { my $pass; \$pass });
}

# Values qw( done:send done:abort ) or empty
sub finref {
    my ($self) = @_;
    return ($self->{'_finref'} ||= do { my $var=''; \$var });
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



sub _prompt_sub {
    my ($self, $bolc) = @_;
    return $self->get_password;
}

sub _passwarn_sub {
    my ($self,
        $bolc, $msg) # the B:O:L:Client and message
      = @_;

    $self->logger->warn("passwarn: $msg");
    my $dialog = $self->top->DialogBox
      (-title => $Bio::Otter::Lace::Client::PFX.'Problem logging in',
       -buttons => ['Ok'],);
    $dialog->add(qw( Label -justify left -text ), $msg)->pack;
    $dialog->Show;
    $self->logger->info('passwarn [ok]d');
    return;
}

1;

__END__

=head1 NAME - EditWindow::Password

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

