
package TransientWindow::LogWindow;

use strict;
use warnings;

use IO::Handle;
use Bio::Otter::LogFile;
use Bio::Vega::Utils::URI qw{ open_uri };
use Net::Domain qw{ hostfqdn };


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
        -text    => 'Report bug',
        -command => $email_dev,
    )->pack(-side => 'left');

    $but_frame->Button(
        -text    => 'Close',
        -command => sub { $self->hide_me },
    )->pack(-side => 'right');

    $lw->Tk::bind('<Escape>', [ $self, 'hide_me' ]);
    $lw->Tk::bind('<Control-w>', [ $self, 'hide_me' ]);
    $lw->Tk::bind('<Control-W>', [ $self, 'hide_me' ]);

    $but_frame->bind('<Destroy>', sub { $self = undef; });

    return;
}

sub draw {
    my ($self) = @_;
    return if $self->{'_drawn'};

    my $file      = $self->current_logfile;
    my $tail_pipe = "tail -f -n 1000 $file";
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

    # Limit size of report - some email clients truncate long mailto URLs
    return $txt->get('end - 250 lines', 'end');
}

sub mail_contents {
    my ($self) = @_;

    my $to      = $email . '@' . $domain;
    my $file    = hostfqdn() . ":" . $self->current_logfile;
    my $subj    = "otterlace error: <PLEASE REPLACE WITH SHORT DESCRIPTION>";
    my $mess    = $self->get_log_contents();
    my $info   =
        "Program version: " . Bio::Otter::Git->param('head') . "\n"
        . "Program script name: $0\n"
        . "Log file: $file\n";

    open_uri("mailto:$to", {
        subject => $subj,
        body    => "\n<ADD FURTHER INFORMATION ABOUT PROBLEM HERE>\n\n--------\n$info--------\n$mess",
    }) or warn "Error opening email client to send email to '$to'";

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

