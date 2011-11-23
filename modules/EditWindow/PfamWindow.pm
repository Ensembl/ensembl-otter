### EditWindow::PfamWindow
package EditWindow::PfamWindow;
use strict;
use warnings;
use Carp;
use Bio::Otter::Lace::Pfam;
use Tk::ProgressBar;
use POSIX();
use base 'EditWindow';
my $POLL_ATTEMPTS = 30;
my %WIDGETS;

sub new {
    my ( $pkg, @args ) = @_;
    my $self         = $pkg->SUPER::new(@args);

    return $self;
}

sub progress {
    my ( $self, $p ) = @_;
    if ($p) {
        $self->{_progress} = $p;
    }
    return $self->{_progress};
}

sub pfam {
    my ( $self, $pfam ) = @_;
    $self->{_pfam} = $pfam if $pfam;
    return $self->{_pfam};
}

sub query {
    my ( $self, $s ) = @_;
    if ($s) {
        $self->{_seq} = $s;
    }
    return $self->{_seq};
}

sub name {
    my ( $self, $n ) = @_;
    if ($n) {
        $self->{_name} = $n;
    }
    return $self->{_name};
}

sub status {
    my ( $self, $s ) = @_;
    if ($s) {
        $self->{_status} = $s;
    }
    return $self->{_status};
}

sub result_url {
    my ( $self, $u ) = @_;
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

    $top->bind( '<Control-q>', $cancel_command );
    $top->bind( '<Control-Q>', $cancel_command );
    $top->protocol( 'WM_DELETE_WINDOW', $cancel_command );



    $WIDGETS{'Progress_bar'} = $top->ProgressBar(
                       -width       => 20,
                       -from        => 0,
                       -to          => 100,
                       -blocks      => 1,
                       -variable    => \$self->{_progress}
    )->pack( -fill => 'x' , -expand => 1);

    $WIDGETS{'Status_label'} = $top->Label(
                 -width        => 45,
                 -height       => 1,
                 -textvariable => \$self->{_status}
    )->pack( -side => 'top', -fill => 'x' );

    $WIDGETS{'Cancel_button'} = $top->Button(
                -text    => 'Cancel',
                -command => $cancel_command,
    )->pack( -side => 'top' );

    my ( $result_url, $estimated_time );
    if($self->result_url) {
        ( $result_url, $estimated_time ) = ($self->result_url , 1);
    } else {
        my $xml = $pfam->submit_search( $self->query );
        ( $result_url, $estimated_time ) = $pfam->check_submission($xml);
        $self->result_url($result_url);
    }

    $self->status("searching pfam (wait $estimated_time sec)");
    my $wait = $estimated_time / 30;

    for ( my $block = 1 ; $block <= 30 ; $block++ ) {
        $self->progress($block);
        $self->top->toplevel->update;
        eval {
            $self->top->toplevel->after($wait * 1000);
        };
        if ($@) {
            # catch "XStoSubCmd: Not a Tk Window" error when the search is canceled
            return;
        }
    }
    my $tries = 1;
    $wait = 0;
    my $res;
    while ( $tries < $POLL_ATTEMPTS ) {
        $self->progress( 30 + $tries );
        $res = $pfam->poll_results($self->result_url);
        if ($res && $res =~ /<pfam/m ) {
            $self->fill_progressBar(60);
            last;
        }
        $self->status("searching pfam (status $res)");
        $self->top->toplevel->update;
        $wait += $tries;
        $tries++;
        eval {
            $self->top->toplevel->after($wait * 1000);
        };
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
        if(@domains) {
            my $blocks_per_domain = 30 / scalar(@domains);
            foreach my $domain (sort @domains) {
                my $sub_seq = $pfam->get_seq_snippets($self->name,$self->query,$matches->{$domain}->{locations});
                $self->status("$domain: get the seed aligments");
                $self->top->toplevel->update;
                my $s = $pfam->retrieve_pfam_seed([$domain]);
                my $seed = $s->{$domain};

                $self->status("$domain: get the hmm");
                $self->top->toplevel->update;
                my $h = $pfam->retrieve_pfam_hmm([$domain]);
                my $hmm = $h->{$domain};

                $self->status("$domain: aligning");
                $self->top->toplevel->update;
                my $alignment_file = $pfam->align_to_seed($sub_seq,$domain,$hmm,$seed);
                $alignments->{$domain} = $alignment_file;
                $self->fill_progressBar($blocks_per_domain + $self->progress);
            }
        }

        $self->fill_progressBar(100);
        $self->status("Significant Pfam-A Matches :");
        $self->top->toplevel->update;

        $WIDGETS{'Padding_frame'} = $top->Frame->pack( -side => 'top', -fill => 'both');
        $WIDGETS{'Result_frame'} = $top->Frame->pack( -side => 'top', -fill => 'both');

        # display result
        if(keys %$alignments) {

            # Widget Pfam_label isa Label
            $WIDGETS{'Pfam_label'} = $WIDGETS{Result_frame}->Label(
               -text        => 'Pfam',
               -width       => 10,
              )->grid(-column => 0 , -row => 0);

            # Widget ID_label isa Label
            $WIDGETS{'ID_Class_label'} = $WIDGETS{Result_frame}->Label(
               -text   => 'ID & Class',
               -width  => 20,
              )->grid(
               -row    => 0,
               -column => 1,
              );

            # Widget Locations_label isa Label
            $WIDGETS{'Locations_label'} = $WIDGETS{Result_frame}->Label(
               -text       => 'Locations',
               -width      => 10,
              )->grid(
               -row    => 0,
               -column => 2,
              );

            # Widget Alignments_label isa Label
            $WIDGETS{'Alignments_label'} = $WIDGETS{Result_frame}->Label(
               -text   => 'Alignments',
               -width  => 10,
              )->grid(
               -row    => 0,
               -column => 3,
              );
        }



        my $row = 1;

        foreach my $domain (keys %$alignments) {
            my $locations = "";
            my $m = scalar @{$matches->{$domain}->{locations}};
            for my $location (sort {$a->{start} <=> $b->{start} } @{$matches->{$domain}->{locations}}) {
                $locations .= $location->{start}."->".$location->{end}." ";
            }

            # Widget Pfam_entry isa Entry
            $WIDGETS{'Pfam_entry_${domain}'} = $WIDGETS{Result_frame}->Entry(
               -highlightthickness => 0,
               -justify            => 'center',
               -state              => 'readonly',
               -text               => $domain,
               -width              => 10,
              )->grid(
               -row    => $row,
               -column => 0,
              );

            # Widget ID_Class_entry isa Entry
            $WIDGETS{'ID_Class_entry_${domain}'} = $WIDGETS{Result_frame}->Entry(
               -highlightthickness => 0,
               -justify            => 'center',
               -state              => 'readonly',
               -width              => 20,
               -text               => $matches->{$domain}->{id}." ".$matches->{$domain}->{class},
              )->grid(
               -row    => $row,
               -column => 1,
              );


            # Widget Locations_entry isa Entry
            $WIDGETS{'Locations_entry_${domain}'} = $WIDGETS{Result_frame}->Entry(
               -highlightthickness => 0,
               -state              => 'readonly',
               -width              => 10,
               -text               => $locations,
              )->grid(
               -row    => $row,
               -column => 2,
              );

            # Widget Belvu_butto isa Button
            my $launch_belvu = sub {
                        if (my $pid = fork) {
                            return 1;
                        }
                        elsif (defined $pid) {
                            my $command = "belvu ".$alignments->{$domain};
                            exec($command) or warn "Failed to exec '$command' : $!";
                        }
            };

            $WIDGETS{'Belvu_butto'} = $WIDGETS{Result_frame}->Button(
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
              $row ++;
        }

        $self->open_url();
    }
    else {
        $self->status("open pfam manually");
        $self->top->toplevel->update;
    }

    $WIDGETS{'Progress_bar'}->packForget;
    $WIDGETS{'Cancel_button'}->packForget;

    $WIDGETS{'Button_frame'} = $top->Frame->pack( -side => 'top', -fill => 'x' );

    $WIDGETS{'Open_button'} = $WIDGETS{'Button_frame'}->Button(
        -text    => 'open Pfam page',
        -command => sub {
            $self->open_url();
        },
    )->pack( -side => 'left' );

    $WIDGETS{'Quit_button'} = $WIDGETS{'Button_frame'}->Button(
                                      -text    => 'Close',
                                      -command => $quit_command,
    )->pack( -side => 'right' );

    $top->bind( '<Control-q>', $quit_command );
    $top->bind( '<Control-Q>', $quit_command );
    $top->protocol( 'WM_DELETE_WINDOW', $quit_command );

    # need to call configure to resize the window.
    # the values in width and height are not important
    $self->top->toplevel->configure(-width => 1 , -height => 1);

    return;
}

sub fill_progressBar {
    my ($self, $value) = @_;

    for ( my $percent = $self->progress ; $percent <= $value ; $percent++ ) {
        $self->progress($percent);
        $self->top->toplevel->update;
        $self->top->toplevel->after(20);
    }

    return;
}

sub open_url {
    my ($self) = @_;
    my $url = $self->result_url;
    $url =~ s/output=xml&?//;
    $url =~ s/resultset/results/;
    print STDOUT "Pfam search result for " . $self->name . "\n$url\n";
    if ( $^O eq 'darwin' ) {
        system("open '$url'");
    }
    else {
        # run in the background to avoid hanging the Otterlace GUI
        return unless fork;
        POSIX::_exit(0) unless fork;
        my @commands = (qq{firefox -remote "openURL($url,new-tab)"},
                        qq{iceape -remote "openURL($url,new-tab)"},
                        qq{mozilla -remote "openURL($url,new-tab)"},
                        qq{firefox $url},
                        qq{iceape $url},
                        qq{mozilla $url},
                        qq{echo 'you must install firefox web browser'});
        my $success = 1;

        for(my $i = 0;($i < scalar(@commands) && $success != 0); $i++) {
            $success = system($commands[$i]);
        }
        POSIX::_exit(0);
    }

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

