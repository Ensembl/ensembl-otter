
### EditWindow::Exonerate

package EditWindow::Exonerate;

use strict;
use warnings;
use Carp;

use Hum::Pfetch;
use Hum::FastaFileIO;
use Hum::ClipboardUtils qw{ accessions_from_text };
use Hum::Sort qw{ ace_sort };
use Tk::LabFrame;
use Tk::Checkbutton;
use Tk::Radiobutton;

use base 'EditWindow';

my $BEST_N            = 1;
my $MAX_INTRON_LENGTH = 200000;
my $MAX_QUERY_LENGTH  = 10000;
my $MASK_TARGET       = 'soft';

my $INITIAL_DIR = (getpwuid($<))[7];

sub initialise {
    my ($self) = @_;

    my @frame_pack = (-side => 'top', -fill => 'x');
    my @frame_expand = (-side => 'top', -fill => 'both', -expand => 1);

    my $top = $self->top;

    ### Query frame
    my $query_frame = $top->LabFrame(
        -label     => 'Query sequences',
        -labelside => 'acrosstop',
        -border    => 3,
    )->pack(@frame_expand);

    ## Accession entry box
    my $match_frame = $query_frame->Frame(-border => 3)->pack(@frame_pack);
    $match_frame->Label(
        -text   => 'Accessions:',
        -anchor => 's',
        -padx   => 6,
    )->pack(-side => 'left');
    $self->match($match_frame->Entry->pack(-side => 'left', -expand => 1, -fill => 'x'));
    $match_frame->Frame(-width => 6,)->pack(-side => 'left');

    my $update = sub {
        $self->accessions_from_clipboard;
    };
    $match_frame->Button(
        -text      => 'Fetch from clipboard',
        -underline => 0,
        -command   => $update,
    )->pack(-side => 'left');
    $match_frame->Button(
        -text      => 'Clear',
        -underline => 0,
        -command   => sub {
            $self->set_entry('match', '');
            $self->fasta_txt->delete('1.0', 'end');
        },
    )->pack(-side => 'left');
    $top->bind('<Control-u>', $update);
    $top->bind('<Control-U>', $update);

    ## Fasta file entry box
    my $fname;
    my $file_frame = $query_frame->Frame(-border => 3)->pack(@frame_pack);
    $file_frame->Label(
        -text   => 'Fasta file:',
        -anchor => 's',
        -padx   => 6,
    )->pack(-side => 'left');

    $self->fasta_file($file_frame->Entry(-textvariable => \$fname)->pack(-side => 'left', -expand => 1, -fill => 'x'));

    # Pad between entries
    $file_frame->Frame(-width => 6,)->pack(-side => 'left');

    $file_frame->Button(
        -text    => 'Browse...',
        -command => sub {
            $fname = $top->getOpenFile(
                -title      => 'otter: Choose Fasta File',
                -initialdir => $INITIAL_DIR,
                -filetypes  => [

                    # ['Fasta Files'  => [qw{ .seq .pep .dna .fasta .fa }]],
                    # ['All Files'    => '*'],

                    # Do not want to show hidden files.
                    [
                        'Fasta Files (*.seq,*.pep,*.dna,*.fasta,*.fa)' => sub {
                            my ($widget, $file, $dir) = @_;

                            # Match non-hidden files which end with one of our extensions
                            return $file =~ /^[^\.].*\.(seq|pep|dna|fasta|fa)$/;
                          }
                    ],
                    [
                        'All Files (*)' => sub {
                            my ($widget, $file, $dir) = @_;

                            # Match non-hidden files
                            return $file !~ /^\./;
                          }
                    ],
                ],

                # This option is present in our patched Tk::FBox
                # module which you can find in our Tk directory.
                -sortcmd => sub { ace_sort(@_) },
            );
            if ($fname) {
                if (my ($dir) = $fname =~ m{^(.+?)[^/]+$}) {

                    # warn "Setting inital dir to '$dir'";
                    $INITIAL_DIR = $dir;
                }
            }

            # Show the end of the Entry, so that when the file path is long the
            # user can see the name of the file which was chosen.
            $self->fasta_file->xviewMoveto(1);
        }
    )->pack(-side => 'left');

    ## Sequence text box
    my $txt_frame = $query_frame->Frame(-border => 3)->pack(@frame_expand);
    $txt_frame->Label(
        -text   => 'Fasta sequence:',
        -anchor => 'w',
        -padx   => 6,
    )->pack(@frame_pack);
    $self->fasta_txt(
        $txt_frame->Scrolled(
            "Text",

            # -background => 'white',
            -height     => 12,
            -width      => 62,
            -scrollbars => 'se',
            -font       => $self->XaceSeqChooser->font_fixed,
          )->pack(@frame_expand)
    );

    ### Parameters
    my $param_frame = $top->LabFrame(
        -label     => 'Parameters',
        -labelside => 'acrosstop',
        -border    => 3,
    )->pack(@frame_pack);

    my $repeat_radio_frame = $param_frame->LabFrame(
        -label     => 'Repeat masking',
        -labelside => 'acrosstop',
        -border    => 3,
    )->pack(-side => 'bottom', -fill => 'y');

    $self->{_mask_target} = $MASK_TARGET;

    $repeat_radio_frame->Radiobutton(
        -variable => \$self->{_mask_target}, 
        -text     => 'Unmasked',
        -value    => 'none',
    )->pack(-side => 'left', -expand => 1, -fill => 'x');

    $repeat_radio_frame->Radiobutton(
        -variable => \$self->{_mask_target}, 
        -text     => 'Soft masked',
        -value    => 'soft',
    )->pack(-side => 'left', -expand => 1, -fill => 'x');

    my $option_frame = $param_frame->Frame->pack(-side => 'right', -fill => 'x');

    my $bestn_frame = $option_frame->Frame->pack(@frame_pack);

    $self->bestn(
        $bestn_frame->Entry(
            -width   => 9,
            -justify => 'right',
          )->pack(-side => 'right')
    );

    $self->set_entry('bestn', $BEST_N);

    $bestn_frame->Label(
        -text   => 'Number of transcript alignments to report (0 for all):',
        -anchor => 'e',
        -padx   => 6,
    )->pack(-side => 'right', -fill => 'x');

    my $intron_length_frame = $option_frame->Frame->pack(-side => 'bottom', -fill => 'x');

    $self->max_intron_length(
        $intron_length_frame->Entry(
            -width   => 9,
            -justify => 'right',
          )->pack(-side => 'right')
    );

    $self->set_entry('max_intron_length', $MAX_INTRON_LENGTH);

    $intron_length_frame->Label(
        -text   => 'Maximum intron length:',
        -anchor => 'e',
        -padx   => 6,
    )->pack(-side => 'right', -fill => 'x');

    my $cb_frame = $param_frame->Frame->pack(-side => 'left', -fill => 'x');

    $cb_frame->Checkbutton(
        -variable => \$self->{_clear_existing},
        -text     => 'Clear existing OTF alignments',
        -anchor   => 'w',
    )->pack(-side => 'top', -expand => 1, -fill => 'x');

    $self->{_use_marked_region} = 1;

    $cb_frame->Checkbutton(
        -variable => \$self->{_use_marked_region},
        -text     => 'Only search within marked region',
        -anchor   => 'w',
    )->pack(-side => 'top', -expand => 1, -fill => 'x');

    ### Commands
    my $button_frame = $top->Frame->pack(@frame_pack);
    my $launch       = sub {
        $self->launch_exonerate or return;
        $top->withdraw;
    };
    $button_frame->Button(
        -text      => 'Launch',
        -underline => 0,
        -command   => $launch,
    )->pack(-side => 'left');
    $top->bind('<Control-l>', $launch);
    $top->bind('<Control-L>', $launch);

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

    return;
}

sub update_from_XaceSeqChooser {
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
    if (my @acc = accessions_from_text($text)) {
        $self->set_entry('match', join ' ', @acc);

        # Show the end of the Entry so that the annotator sees
        # the latest accessions added.
        $self->match->xviewMoveto(1);
    }

    return;
}

sub set_entry {
    my ($self, $method, $txt) = @_;
    my $entry = $self->$method();

    my $reset = 0;
    if ($entry->cget('-state') eq 'readonly') {
        $entry->configure(-state => 'normal');
        $reset = 1;
    }

    $entry->delete(0, 'end');
    $entry->insert(0, $txt);

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

sub fasta_txt {
    my ($self, $txt) = @_;
    if ($txt) {
        $self->{'_fasta_txt'} = $txt;
    }
    return $self->{'_fasta_txt'};
}

sub fasta_file {
    my ($self, $file) = @_;
    if ($file) {
        $self->{'_fasta_file'} = $file;
    }
    return $self->{'_fasta_file'};
}

sub bestn {
    my ($self, $bestn) = @_;
    if ($bestn) {
        $self->{'_bestn'} = $bestn;
    }
    return $self->{'_bestn'};
}

sub max_intron_length {
    my ($self, $max_intron_length) = @_;
    if ($max_intron_length) {
        $self->{'_max_intron_length'} = $max_intron_length;
    }
    return $self->{'_max_intron_length'};
}

sub match {
    my ($self, $match) = @_;
    if ($match) {
        $self->{'_match'} = $match;
    }
    return $self->{'_match'};
}

sub XaceSeqChooser {
    my ($self, $xc) = @_;
    if ($xc) {
        $self->{'_xc'} = $xc;
    }
    return $self->{'_xc'};
}

sub launch_exonerate {

    my ($self) = @_;

    my $seqs;

    $seqs = $self->get_query_seq();

    print STDERR "Found " . scalar(@$seqs) . " sequences\n";

    unless (@$seqs) {
        $self->top->messageBox(
            -title   => 'otter: No Sequence',
            -icon    => 'warning',
            -message => 'Did not get any sequence data',
            -type    => 'OK',
        );
        return;
    }

    $self->top->Busy;

    if ($self->{'_clear_existing'}) {
        $self->XaceSeqChooser->delete_featuresets(qw{
Unknown_DNA
Unknown_Protein
OTF_EST
OTF_ncRNA
OTF_mRNA
OTF_Protein });
    }

    my %exonerate_params = (
        -use_marked_region => $self->{_use_marked_region},
        -best_n            => ($self->get_entry('bestn') || 0),
        -max_intron_length => ($self->get_entry('max_intron_length') || 0),
        -mask_target       => $self->{_mask_target},
        );
    my $need_relaunch =
        $self->XaceSeqChooser->launch_exonerate($seqs, \%exonerate_params);

    $self->top->Unbusy;

    if ($need_relaunch) {
        return 1;
    }
    else {
        $self->top->messageBox(
            -title   => 'otter: No Matches',
            -icon    => 'warning',
            -message => 'Exonerate did not find any matches on genomic sequence',
            -type    => 'OK',
        );
        return 0;
    }
}

my $seq_tag = 1;

sub get_query_seq {
    my ($self) = @_;
    my @seqs;

    # get seqs from fasta file and text box

    if (my $string = $self->fasta_txt->get('1.0', 'end')) {
        if ($string =~ /\S/ and $string !~ />/) {
            warn "creating new seq tag num: $seq_tag\n";
            $string = ">OTF_seq_$seq_tag\n" . $string;
            $seq_tag++;
        }
        push @seqs, Hum::FastaFileIO->new(\$string)->read_all_sequences;
    }
    if (my $file_name = $self->get_entry('fasta_file')) {
        # Trim trailing or leading whitespace from file name
        $file_name =~ s/^\s+|\s+$//g;
        push @seqs, Hum::FastaFileIO->new($file_name)->read_all_sequences;
    }

    my @accessions = map { $_->name } @seqs;

    # get seqs from accession numbers supplied by the user

    my @supplied_accs;
    if (my $txt = $self->get_entry('match')) {
        $txt =~ s/^\s+//;
        $txt =~ s/\s+$//;
        @supplied_accs = split(/[,;\|\s]+/, $txt);
        push @accessions, @supplied_accs;
    }

    # identify the types of all the accessions supplied

    my $cache = $self->XaceSeqChooser->AceDatabase->AccessionTypeCache;
    # The populate method will fetch the latest version of
    # any accessions which are supplied without a SV into
    # the cache object.
    $cache->populate(\@accessions);

    # add type and full accession information to the existing sequences
    my ($missing_msg, $remapped_msg);
    for my $seq (@seqs) {
        my $name = $seq->name;
        if (my ($type, $full_acc) = $cache->type_and_name_from_accession($name)) {
            ### Might want to be paranoid and check that the sequence of
            ### supplied sequences matches the pfetched sequence where the
            ### names of sequences are public accessions.
            $seq->type($type);
            $seq->name($full_acc);
            if ($name ne $full_acc) {
                $remapped_msg .= "  $name to $full_acc\n";
            }
        }
    }

    my (%acc_type_full, @to_pfetch);
    for (my $i = 0; $i < @supplied_accs;) {
        my $acc = $supplied_accs[$i];
        my ($type, $full) = $cache->type_and_name_from_accession($acc);
        if ($type and $full) {
            $i++;
            $acc_type_full{$acc} = [$type, $full];            
            push(@to_pfetch, $full);
        }
        else {
            # No point trying to pfetch invalid accessions
            $missing_msg .= "  $acc unknown accession\n";
            splice(@supplied_accs, $i, 1);
        }
    }

    my %seqs_fetched;
    if (@to_pfetch) {
        foreach my $seq (Hum::Pfetch::get_Sequences(@to_pfetch)) {
            $seqs_fetched{$seq->name} = $seq;
        }
    }

    foreach my $acc (@supplied_accs) {
        my ($type, $full) = @{$acc_type_full{$acc}};
        
        # Delete from the hash so that we can check for
        # unclaimed sequences.
        my $seq = delete($seqs_fetched{$full});
        if ($seq) {
            $seq->type($type);
        }
        else {
            $missing_msg .= "  $acc ($full) could not pfetch\n";
            next;
        }
        
        if ($full ne $acc) {
            $remapped_msg .= "  $acc to $full\n";
        }

        push(@seqs, $seq);
    }

    # tell the user about any missing sequences or remapped accessions

    if ($missing_msg || $remapped_msg || keys %seqs_fetched) {
        $missing_msg =
          "I did not find any sequences for the following accessions:\n\n$missing_msg\n"
            if $missing_msg;

        $remapped_msg =
          "The following supplied accessions have been mapped to full ACCESSION.SV:\n\n$remapped_msg\n"
            if $remapped_msg;

        my $unclaimed_msg = '';
        if (keys %seqs_fetched) {
            $unclaimed_msg =
              "The following sequences were fetched, but didn't map back to supplied names:\n\n"
                . join('', map { "  $_\n" } keys %seqs_fetched);
        }

        $self->top->messageBox(
            -title   => 'otter: Problems With Accessions Supplied',
            -icon    => 'warning',
            -message => $missing_msg . $remapped_msg . $unclaimed_msg,
            -type    => 'OK',
        );
    }

    # check for unusually long query sequences

    my @confirmed_seqs;

    for my $seq (@seqs) {
        if ($seq->sequence_length > $MAX_QUERY_LENGTH) {
            my $response = $self->top->messageBox(
                -title   => 'otter: Unusually Long Query Sequence',
                -icon    => 'warning',
                -message => $seq->name . " is "
                  . $seq->sequence_length
                  . " residues long.\n"
                  . "Are you sure you want to try to align it?",
                -type => 'YesNo',
            );

            if ($response eq 'Yes') {
                push @confirmed_seqs, $seq;
            }
        }
        else {
            push @confirmed_seqs, $seq;
        }
    }

    return \@confirmed_seqs;
}

sub DESTROY {
    my ($self) = @_;

    warn "Freeing exonerateWindow '$self'\n";

    return;
}

1;

__END__

=head1 NAME - EditWindow::Exonerate

=head1 AUTHOR

Anacode B<email> anacode@sanger.ac.uk

