=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


### EditWindow::FetchDB

package EditWindow::FetchDb;

use strict;
use warnings;

use Bio::Otter::Log::Log4perl 'logger';
use Readonly;
use Try::Tiny;
use Bio::Otter::Lace::Client;
use Bio::Otter::Lace::OnTheFly::Genomic;
use Bio::Vega::Evidence::Types qw( evidence_is_sra_sample_accession seq_is_protein );
use Hum::ClipboardUtils qw{ accessions_from_text };
use Hum::Sort qw{ ace_sort };
use Tk::LabFrame;
use Tk::Checkbutton;
use Tk::Radiobutton;

use base qw{
    EditWindow
    Bio::Otter::UI::OnTheFlyMixin
    };

my $BEST_N            = 1;
my $MAX_INTRON_LENGTH = 200000;
my $MAX_QUERY_LENGTH  = 10000;

my $REGION_TARGET_ALL     = 'all';
my $REGION_TARGET_MARKED  = 'marked';
my $REGION_TARGET_DEFAULT = $REGION_TARGET_MARKED;

my $MASK_TARGET_NONE    = 'none';
my $MASK_TARGET_SOFT    = 'soft';
my $MASK_TARGET_DEFAULT = $MASK_TARGET_NONE;

my $INITIAL_DIR = (getpwuid($<))[7];

sub initialise {
    my ($self) = @_;

    my @frame_pack = (-side => 'top', -fill => 'x');
    my @frame_expand = (-side => 'top', -fill => 'both', -expand => 1);

    my $top = $self->top;

    ### Query frame
    my $query_frame = $top->LabFrame(
        Name       => 'query',
        -label     => 'Query sequences',
        -border    => 3,
    )->pack(@frame_expand);

    ## Accession entry box
    my $match_frame = $query_frame->Frame(-border => 3)->pack(@frame_pack);
    $match_frame->Label(
        -text   => 'Accessions:',
        -anchor => 's',
    )->pack(-side => 'left');
    $self->match($match_frame->Entry->pack(-side => 'left', -expand => 1, -fill => 'x'));

    my $update = sub {
        $self->accessions_from_clipboard;
    };

    $match_frame->Button(
        -text      => 'Fetch from clipboard',
        -underline => 0,
        -command   => $update,
    )->pack(-side => 'left', -padx => 4);

    $match_frame->Button(
        -text      => 'Clear',
        -underline => 0,
        -command   => sub { $self->clear_accessions },
    )->pack(-side => 'left');
    $top->bind('<Control-u>', $update);
    $top->bind('<Control-U>', $update);

    ## Sequence text box
    my $txt_frame = $query_frame->Frame(-border => 3)->pack(@frame_expand);
    $txt_frame->Label(
        -text   => 'Sequence:',
        -anchor => 'w',
    )->pack(@frame_pack);
    $self->sequence_txt(
        $txt_frame->Scrolled(
            "Text",
            # -background => 'white',
            -height     => 12,
            -width      => 62,
            -scrollbars => 'se',
            -font       => $self->SessionWindow->font_fixed,
          )->pack(@frame_expand)
    );

    ### Commands
    my $button_frame = $top->Frame(
        Name    => 'button',
        -border => 2,
        )->pack(@frame_pack);
    my $doing_launch = 0;       # captured by closure...
    my $launch       = sub {
        if ($doing_launch) {
            $self->logger->warn("Already launched, ignoring click.");
            return;
        }
        $doing_launch = 1;
        try {
            $self->launch_fetchdb;
        }
        catch {
            my $err = $_;
            $self->top->messageBox(
                -title   => $Bio::Otter::Lace::Client::PFX.'Error',
                -icon    => 'warning',
                -message => 'Error running fetchDb: ' . $err,
                -type    => 'OK',
            );
            $self->logger->error('Error running fetchDb: ', $err);
        };
        $doing_launch = 0;
    };
    $button_frame->Button(
        -text      => 'Launch',
        -underline => 0,
        -command   => $launch,
    )->pack(-side => 'left');
    $top->bind('<Control-l>', $launch);
    $top->bind('<Control-L>', $launch);

    # Progress
    $button_frame->Label(
        -width        => 45,
        -height       =>  1,
        -textvariable => \$self->{_progress},
    )->pack(-side => 'left', -expand => 1, -fill => 'x', -padx => 6);

    # Manage window closes and destroys
    my $close_window = sub { $top->withdraw };
    $button_frame->Button(
        -text    => 'Close',
        -command => $close_window,
    )->pack(-side => 'right');
    $top->bind('<Control-w>', $close_window);
    $top->bind('<Control-W>', $close_window);
    $top->protocol('WM_DELETE_WINDOW', $close_window);
    $top->bind('<Destroy>', sub { $self = undef; });
    $self->set_minsize;

    $self->colour_init;

    return;
}

sub update_from_SessionWindow {
    my ($self) = @_;
    $self->accessions_from_clipboard;
    my $top = $self->top;
    $top->deiconify;
    $top->raise;
    return;
}

sub query_Sequence {
    my ($self, $query_Sequence) = @_;
    if ($query_Sequence) {
        $self->{'_query_Sequence'} = $query_Sequence;
    }
    return $self->{'_query_Sequence'};
}

sub sequence_txt {
    my ($self, $txt) = @_;
    if ($txt) {
        $self->{'sequence_txt'} = $txt;
    }
    return $self->{'sequence_txt'};
}

sub accessions_from_clipboard {
    my ($self) = @_;

    my $text = $self->get_clipboard_text or return;

    # Add clipboard text to existing entry text so that annotator
    # can easily build up a list of accessions to search
    if (my $entry_txt = $self->get_entry('match')) {
        $text = join(' ', $entry_txt, $text);
    }

    # accessions_from_text extracts all the accessions from its
    # text argument and removes duplicates from the list

    # Temporary fix to eliminate SRA accessions from dotter / OTF vs transcript.
    my @acc = grep { not evidence_is_sra_sample_accession($_) } accessions_from_text($text);

    if (@acc) {
        $self->set_entry('match', join ' ', @acc);

        # Show the end of the Entry so that the annotator sees
        # the latest accessions added.
        $self->match->xviewMoveto(1);
    }

    return;
}

sub match {
    my ($self, $match) = @_;
    if ($match) {
        $self->{'_match'} = $match;
    }
    return $self->{'_match'};
}


sub set_entry {
    my ($self, $method, $txt) = @_;
    my $entry = $self->$method();

    my $reset = 0;
    if ($entry->cget('-state') eq 'readonly') {
        $entry->configure(-state => 'normal');
        $reset = 1;
    }
    $entry->delete('1.0','end');
    $entry->insert('end', $txt);

    $entry->configure(-state => 'readonly') if $reset;

    return;
}

sub get_entry {
    my ($self, $method) = @_;

    if (my $txt = $self->$method()->get) {
        if ($txt =~ /\S/) {
            return $txt;
        }
    }
    return;
}

sub clear_accessions {
    my ($self) = @_;
    $self->set_entry('match', '');
    $self->set_entry('sequence_txt', "");
    return;
}

sub SessionWindow {
    my ($self, $SessionWindow) = @_;
    if ($SessionWindow) {
        $self->{'_SessionWindow'} = $SessionWindow;
    }
    return $self->{'_SessionWindow'};
}

sub launch_fetchdb {
    my ($self) = @_;
    my $accessions = $self->entered_accessions;

    $self->_fetch_sequences($accessions);
    return 1;
}

sub _fetch_sequences {
  my ($self, $to_fetch) = @_;

  my $client = Bio::Otter::Lace::Defaults::make_Client();
  my $seq = $client->fetch_seqence($to_fetch);
  $self->set_entry('sequence_txt', join ' ', $seq);

  return;
}

sub Client {
    my ($self, $client) = @_;

    if ($client) {
        $self->{'_Client'} = $client;
        $self->colour( $self->next_session_colour );
    }
    return $self->{'_Client'};
}

sub progress {
    my ($self, @args) = @_;
    if (@args) {
        ($self->{_progress}) = @args;
        my $top = $self->top;
        $top->toplevel->update if Tk::Exists($top);
    }
    return $self->{_progress};
}

sub display_request_feedback {
    my ($self, $request) = @_;
    $self->report_missed_hits($self->SessionWindow, $request, 'genomic');
    return;
}

Readonly my $SEQ_TAG_STEM => 'OTF_seq_';


# get seqs from accession numbers supplied by the user
#
sub entered_accessions {
    my ($self) = @_;

    my @supplied_accs;
    if (my $txt = $self->get_entry('match')) {
        $txt =~ s/^\s+//;
        $txt =~ s/\s+$//;
        @supplied_accs = split(/[,;\|\s]+/, $txt);
    }
    return $supplied_accs[0];
}

sub _tidy_pasted_sequence {
    my ($self, $seq) = @_;
    open my $fh, '<', \$seq or $self->logger->logdie('open stringref failed');
    my @stripped;
    while (my $line = <$fh>) {
        chomp $line;
        unless ($line =~ /^>/) {
            $line =~ s{       # strip leading line numbers:
                          ^   #   start of line
                          \s* #   optional leading whitespace
                          \d+ #   line number
                          \s+ #   at least some whitespace
                      }{}x;
            $line =~ s/\s+//g; # strip whitespace
        }
        push @stripped, $line if $line;
    }
    push @stripped, '';         # ensure trailing newline
    return join("\n", @stripped);
}

sub DESTROY {
    my ($self) = @_;

    warn "Freeing fetchDbWindow '$self'\n";

    return;
}

1;

__END__

=head1 NAME - EditWindow::FetchDb

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
