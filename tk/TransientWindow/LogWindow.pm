
package TransientWindow::LogWindow;

use strict;
use warnings;

use IO::Handle;
use Bio::Otter::LogFile;

use base qw( TransientWindow );

my $email     = q(anacode);
my $domain    = q(sanger.ac.uk);
my @mail      = qw(smtp Server localhost);
my $loggingOn = 0;

sub initialise {
    my ($self, @args) = @_;

    $self->SUPER::initialise(@args);

    my $lw        = $self->window;
    my $top_frame = $lw->Frame->pack(
        -side   => 'top',
        -fill   => 'both',
        -expand => 1
    );
    my $but_frame = $lw->Frame->pack(
        -side => 'top',
        -fill => 'x'
    );
    my $scrolled = $top_frame->Scrolled(
        'ROText',
        -font             => [ 'lucidatypewriter', 10, 'normal' ],
        -padx             => 6,
        -pady             => 6,
        -relief           => 'groove',
        -background       => 'white',
        -border           => 2,
        -selectbackground => 'gold',
        -scrollbars       => 'se',
        -wrap             => 'none',
        -width            => 100,
        -height           => 24,
      )->pack(
        -expand => 1,
        -fill   => 'both',
      );
    my $ROText = $scrolled->Subwidget('rotext');
    unless ($^O eq 'MSWin32') {
        my $y_scroll = $ROText->parent->Subwidget('yscrollbar');
        $ROText->Tk::bind(
            '<4>',
            sub {
                $y_scroll->ScrlByUnits('v', -3);
            }
        );
        $ROText->Tk::bind(
            '<5>',
            sub {
                $y_scroll->ScrlByUnits('v', +3);
            }
        );
    }
    $self->readonly_text($ROText);

    my $email_dev = sub { $self->mail_contents(); };
    $but_frame->Button(
        -text    => qq(Email $email),
        -command => $email_dev,
    )->pack(-side => 'left');

    $but_frame->Button(
        -text    => 'Close',
        -command => sub { $self->hide_me },
    )->pack(-side => 'right');

    $but_frame->bind('<Destroy>', sub { $self = undef; });

    return;
}

sub draw {
    my ($self) = @_;
    return if $self->{'_drawn'};

    my $file      = $self->current_logfile;
    my $tail_pipe = "tail -f -n 100 $file";
    my $pid       = open my $fh, '-|', $tail_pipe
      or die "Can't open tail command '$tail_pipe': $!";
    $self->tail_process($pid);
    $self->logfile_handle($fh);
    my $txt = $self->readonly_text;
    $txt->fileevent($fh, 'readable', sub { $self->show_output });
    $txt->bind('<Destroy>', sub { $self = undef });

    # Unbuffer filehandle
    $fh->autoflush(1);

    #my $string = $self->get_log_contents();
    #$ROText->delete('1.0', 'end');
    #$ROText->insert('end', $string);

    $self->{'_drawn'} = 1;
    return;
}

sub tail_process {
    my ($self, $tail_process) = @_;

    if ($tail_process) {
        $self->{'_tail_process'} = $tail_process;
    }
    return $self->{'_tail_process'};
}

sub logfile_handle {
    my ($self, $logfile_handle) = @_;

    if ($logfile_handle) {
        $self->{'_logfile_handle'} = $logfile_handle;
    }
    return $self->{'_logfile_handle'};
}

sub current_logfile {
    return Bio::Otter::LogFile::current_logfile();
}

sub readonly_text {
    my ($self, $widget) = @_;

    $self->{'_rotext'} = $widget if $widget;
    return $self->{'_rotext'};
}

sub show_output {
    my ($self) = @_;

    my $fh  = $self->logfile_handle;
    my $txt = $self->readonly_text;
    $txt->insert('end', <$fh>);
    $txt->yview('end');

    return;
}

sub get_log_contents {
    my ($self, $refresh) = @_;

    my $txt = $self->readonly_text;
    return $txt->get('1.0', 'end');
}

sub mail_contents {
    my ($self) = @_;

    my $to     = $email . '@' . $domain;
    my $file   = $self->current_logfile;
    my $subj   = "[$0] error log $file";
    my $dialog = $self->window->toplevel->DialogBox(
        -title          => "otter: Email $to?",
        -buttons        => [qw(Ok Cancel)],
        -default_button => 'Cancel',
    );

    $dialog->add('Label', -text => $subj,)->pack();
    my $pre = '';
    $dialog->add(
        'LabEntry',
        -textvariable => \$pre,
        -label        => 'Description of error: ',
        -width        => 45,
        -background   => 'white',
        -labelPack    => [ -side => 'left' ],
        -font         => [ 'Helvetica', '12', 'normal' ],
    )->pack(-pady => 6,);
    $dialog->add(
        'Label', -text => "Send this error log to '$to'?\n\n".
        "Please note this uses the built-in (system) email transfer\n".
        "configuration.  This often does not work on laptops."
        )->pack();
    $dialog->add(
        'Label', -text =>
        "If you do not receive the automatic acknowledgement email within an\n".
        "hour or so, please contact us by another means.",
        -background => 'black',
        -foreground => 'red'
        )->pack();

    my $result = $dialog->Show();
    return unless $result eq 'Ok';

    my $mess      = $self->get_log_contents();
    my $mail_pipe = qq{mailx -s "$subj" $to};
    open my $fh, '|-', $mail_pipe or die "Error opening '$mail_pipe' : $!";
    print $fh "$pre\n\n$mess";
    close $fh or warn "Error emailing with pipe '$mail_pipe' : exit($?)";

    return;
}

sub DESTROY {
    my ($self) = @_;

    warn "Destroying logfile monitor for '", $self->current_logfile, "'\n";

    if (my $pid = $self->tail_process) {
        kill 'TERM', $pid;
    }
    if (my $fh = $self->logfile_handle) {
        close($fh);
    }

    return;
}

1;

__END__

