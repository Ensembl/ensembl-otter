
package EditWindow::PfamWindow;

use strict;
use warnings;
use Carp;
use POSIX();
use URI;
use Tk::ProgressBar;
use Bio::Otter::Lace::Pfam;
use Bio::Vega::Utils::URI qw{ open_uri };
use Hum::Sort qw{ ace_sort };

use base 'EditWindow';

my $POLL_ATTEMPTS = 30;

sub new {
    my ($pkg, @args) = @_;
    my $self = $pkg->SUPER::new(@args);

    return $self;
}

sub progress {
    my ($self, $p) = @_;
    if ($p) {
        $self->{_progress} = $p;
    }
    return $self->{_progress};
}

sub pfam {
    my ($self, $pfam) = @_;
    $self->{_pfam} = $pfam if $pfam;
    return $self->{_pfam};
}

sub query {
    my ($self, $s) = @_;
    if ($s) {
        $self->{_seq} = $s;
    }
    return $self->{_seq};
}

sub name {
    my ($self, $n) = @_;
    if ($n) {
        $self->{_name} = $n;
    }
    return $self->{_name};
}

sub status {
    my ($self, $s) = @_;
    if ($s) {
        $self->{_status} = $s;
    }
    return $self->{_status};
}

sub result_url {
    my ($self, $u) = @_;
    if ($u) {
        $self->{_url} = $u;
    }
    return $self->{_url};
}

sub initialize {
    my ($self) = @_;

    my $pfam = Bio::Otter::Lace::Pfam->new();
    $self->pfam($pfam);

    my $top = $self->top;

    my $quit_command = sub {
        $top->withdraw;
    };

    my $cancel_command = sub {
        $top->destroy;
    };

    $top->bind('<Control-q>', $cancel_command);
    $top->bind('<Control-Q>', $cancel_command);
    $top->protocol('WM_DELETE_WINDOW', $cancel_command);

    my $progress_bar_widget = $top->ProgressBar(
        -width    => 20,
        -from     => 0,
        -to       => 100,
        -blocks   => 1,
        -variable => \$self->{_progress}
    )->pack(-fill => 'x', -expand => 1);

    $top->Label(
        -width        => 45,
        -height       => 1,
        -textvariable => \$self->{_status}
    )->pack(-side => 'top', -fill => 'x');

    my $cancel_button_widget = $top->Button(
        -text    => 'Cancel',
        -command => $cancel_command,
    )->pack(-side => 'top');

    my ($result_url, $estimated_time);
    if ($self->result_url) {
        ($result_url, $estimated_time) = ($self->result_url, 1);
    }
    else {
        my $xml = $pfam->submit_search($self->query);
        ($result_url, $estimated_time) = $pfam->check_submission($xml);
        $self->result_url($result_url);
    }

    $self->status("searching pfam (wait $estimated_time sec)");
    my $wait = $estimated_time / 30;

    for (my $block = 1; $block <= 30; $block++) {
        $self->progress($block);
        $self->top->toplevel->update;
        eval { $self->top->toplevel->after($wait * 1000); };
        if ($@) {

            # catch "XStoSubCmd: Not a Tk Window" error when the search is canceled
            return;
        }
    }
    my $tries = 1;
    $wait = 0;
    my $res;
    while ($tries < $POLL_ATTEMPTS) {
        $self->progress(30 + $tries);
        $res = $pfam->poll_results($self->result_url);
        if ($res && $res =~ /<pfam/m) {
            $self->fill_progressBar(60);
            last;
        }
        $self->status("searching pfam (status $res)");
        $self->top->toplevel->update;
        $wait += $tries;
        $tries++;
        eval { $self->top->toplevel->after($wait * 1000); };
        if ($@) {

            # catch "XStoSubCmd: Not a Tk Window" error when the search is canceled
            return;
        }
    }

    if ($res) {
        my $alignments = {};

        $self->status("parsing pfam result");
        $self->top->toplevel->update;
        my $matches = $pfam->parse_results($res);
        $self->fill_progressBar(70);
        my @domains = keys %$matches;
        if (@domains) {
            my $blocks_per_domain = 30 / scalar(@domains);
            foreach my $domain (sort @domains) {
                my $sub_seq = $pfam->get_seq_snippets($self->name, $self->query, $matches->{$domain}->{locations});
                $self->status("$domain: get the seed aligments");
                $self->top->toplevel->update;
                my $s    = $pfam->retrieve_pfam_seed([$domain]);
                my $seed = $s->{$domain};

                $self->status("$domain: get the hmm");
                $self->top->toplevel->update;
                my $h   = $pfam->retrieve_pfam_hmm([$domain]);
                my $hmm = $h->{$domain};

                $self->status("$domain: aligning");
                $self->top->toplevel->update;
                my $alignment_file = $pfam->align_to_seed($sub_seq, $domain, $hmm, $seed);
                $alignments->{$domain} = $alignment_file;
                $self->fill_progressBar($blocks_per_domain + $self->progress);
            }
        }

        $self->fill_progressBar(100);
        $self->status("Significant Pfam-A Matches :");
        $self->top->toplevel->update;

        $top->Frame->pack(-side => 'top', -fill => 'both');
        my $result_frame_widget = $top->Frame->pack(-side => 'top', -fill => 'both');

        # display result
        if (keys %$alignments) {

            $result_frame_widget->Label(
                -text  => 'Pfam',
                -width => 10,
            )->grid(-column => 0, -row => 0);

            $result_frame_widget->Label(
                -text  => 'ID & Class',
                -width => 20,
              )->grid(
                -row    => 0,
                -column => 1,
              );

            $result_frame_widget->Label(
                -text  => 'Locations',
                -width => 10,
              )->grid(
                -row    => 0,
                -column => 2,
              );

            $result_frame_widget->Label(
                -text  => 'Alignments',
                -width => 10,
              )->grid(
                -row    => 0,
                -column => 3,
              );
        }

        my $row = 1;

        foreach my $domain (sort { ace_sort($a, $b) } keys %$alignments) {
            my $locations = "";
            my $m         = scalar @{ $matches->{$domain}->{locations} };
            for my $location (sort { $a->{start} <=> $b->{start} } @{ $matches->{$domain}->{locations} }) {
                $locations .= $location->{start} . "->" . $location->{end} . " ";
            }

            $result_frame_widget->Entry(
                -highlightthickness => 0,
                -justify            => 'center',
                -state              => 'readonly',
                -text               => $domain,
                -width              => 10,
              )->grid(
                -row    => $row,
                -column => 0,
              );

            $result_frame_widget->Entry(
                -highlightthickness => 0,
                -justify            => 'center',
                -state              => 'readonly',
                -width              => 20,
                -text               => $matches->{$domain}->{id} . " " . $matches->{$domain}->{class},
              )->grid(
                -row    => $row,
                -column => 1,
              );

            $result_frame_widget->Entry(
                -highlightthickness => 0,
                -state              => 'readonly',
                -width              => 10,
                -text               => $locations,
              )->grid(
                -row    => $row,
                -column => 2,
              );

            my $launch_belvu = sub {
                if (my $pid = fork) {
                    return 1;
                }
                elsif (defined $pid) {
                    my $command = "belvu " . $alignments->{$domain};
                    exec($command) or warn "Failed to exec '$command' : $!";
                }
            };

            $result_frame_widget->Button(
                -anchor             => 's',
                -borderwidth        => 1,
                -highlightthickness => 2,
                -justify            => 'left',
                -padx               => '0m',
                -pady               => '0m',
                -text               => 'in Belvu',
                -width              => 9,
                -command            => \$launch_belvu,
              )->grid(
                -row    => $row,
                -column => 3,
              );
            $row++;
        }

        $self->open_url();
    }
    else {
        $self->status("open pfam manually");
        $self->top->toplevel->update;
    }

    $progress_bar_widget->packForget;
    $cancel_button_widget->packForget;

    my $button_frame_widget = $top->Frame->pack(-side => 'top', -fill => 'x');

    $button_frame_widget->Button(
        -text    => 'View result on Pfam website',
        -command => sub {
            $self->open_url();
        },
    )->pack(-side => 'left');

    $button_frame_widget->Button(
        -text    => 'Close',
        -command => $quit_command,
    )->pack(-side => 'right');

    $top->bind('<Control-q>', $quit_command);
    $top->bind('<Control-Q>', $quit_command);
    $top->protocol('WM_DELETE_WINDOW', $quit_command);

    # need to call configure to resize the window.
    # the values in width and height are not important
    $self->top->toplevel->configure(-width => 1, -height => 1);

    return;
}

sub fill_progressBar {
    my ($self, $value) = @_;

    for (my $percent = $self->progress; $percent <= $value; $percent++) {
        $self->progress($percent);
        $self->top->toplevel->update;
        $self->top->toplevel->after(20);
    }

    return;
}

sub open_url {
    my ($self) = @_;

    my $url = $self->result_url;
    $url =~ s/resultset/results/;

    # Remove query parameters
    my $uri = URI->new($url);
    $uri->query_form({});
    $url = $uri->as_string;

    warn "Pfam search result for " . $self->name . "\n$url\n";
    open_uri($url);
    return;
}

sub DESTROY {
    my ($self) = @_;
    $self = undef;    # $self gets nicely DESTROY'd with this
    return;
}

1;
__END__

=head1 NAME - EditWindow::PfamWindow

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

