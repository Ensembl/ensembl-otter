
### CanvasWindow::DotterWindow

package CanvasWindow::DotterWindow;

use strict;
use Carp;
use Hum::Ace::DotterLauncher;
use Tk::LabFrame;
use base 'CanvasWindow';

sub new {
    my( $pkg, $tk ) = @_;
    
    my $self = bless {}, $pkg;
    $self->top($tk);
    return $self;
}

sub initialise {
    my( $self ) = @_;
    
    my $top = $self->top;
    
    my $dotter = Hum::Ace::DotterLauncher->new;
    $self->dotter($dotter);
        
    # Entry box for match at top
    my $match_frame = $top->Frame(
        -border => 3,
        )->pack(
            -side   => 'top',
            );
    $match_frame->Label(
        -text   => 'Match name:',
        -anchor => 's',
        -padx   => 6,
        )->pack(-side => 'left');
    $self->match(
        $match_frame->Entry(
            -width  => 16,
            )->pack(-side => 'left')
        );
    
    # Pad between entries
    $match_frame->Frame(
        -width  => 10,
        )->pack(-side => 'left');
    
    
    # Whether to open dotter with rev-comp'd match sequence
    my $rev_comp = 0;
    $self->revcomp_ref(\$rev_comp);
    $match_frame->Checkbutton(
        -text       => 'Reverse strand',
        -variable   => \$rev_comp,
        )->pack(-side => 'left');

    
    # Labelled frame around all the Genomic stuff
    my $lab_frame = $top->LabFrame(
        -borderwidth    => 3,
        -label          => 'Genomic sequence',
        -labelside      => 'acrosstop',
        )->pack(
            -side => 'top',
            );
    
    # Name of genomic sequence
    my $name_frame = $lab_frame->Frame->pack(
        -side => 'top',
        -ipady  => 6,
        );
    $name_frame->Label(
        -text   => 'Name:',
        -anchor => 's',
        -padx   => 6,
        )->pack(-side => 'left');
    $self->genomic(
        $name_frame->Entry(
            -width  => 30,
            -state  => 'disabled',
            )->pack(-side => 'left')
        );

    # Length of flank sequence
    my $frame = $lab_frame->Frame->pack(
        -side   => 'top',
        -ipady  => 6,
        );
    $frame->Label(
        -text   => 'Flank:',
        )->pack(-side => 'left');
    $self->flank(
        $frame->Entry(
            -width      => 6,
            -justify    => 'right',
            )->pack(-side => 'left')
        );
    
    # Pad between entries
    $frame->Frame(
        -width  => 10,
        )->pack(-side => 'left');
    
    # Genomic start
    $frame->Label(
        -text   => 'Start:',
        )->pack(-side => 'left');
    $self->genomic_start(
        $frame->Entry(
            -width      => 9,
            -justify    => 'right',
            )->pack(-side => 'left')
        );
    
    # Pad between entries
    $frame->Frame(
        -width  => 10,
        )->pack(-side => 'left');
    
    # Genomic end
    $frame->Label(
        -text   => 'End:',
        )->pack(-side => 'left');
    $self->genomic_end(
        $frame->Entry(
            -width      => 9,
            -justify    => 'right',
            )->pack(-side => 'left')
        );
    
    $self->set_entry('flank', 50_000);
    
    my $button_frame = $top->Frame->pack(
        -side   => 'top',
        -fill   => 'x',
        );
    
    # Launch dotter
    my $launch = sub {
        $self->launch_dotter or return;
        $top->withdraw;
        };
    $button_frame->Button(
        -text       => 'Launch',
        -underline  => 0,
        -command    => $launch,
        )->pack(-side => 'left');
    $top->bind('<Control-l>', $launch);
    $top->bind('<Control-L>', $launch);

    # Update coords
    my $update = sub {
        $self->update_from_clipboard;
        };
    $button_frame->Button(
        -text       => 'Update',
        -underline  => 0,
        -command    => $update,
        )->pack(-side => 'left');
    $top->bind('<Control-u>', $update);
    $top->bind('<Control-U>', $update);

    # Manage window closes and destroys
    my $close_window = sub{ $top->withdraw };
    $button_frame->Button(
        -text       => 'Close',
        -command    => $close_window,
        )->pack(-side => 'right');
    $top->bind('<Control-w>',           $close_window);
    $top->bind('<Control-W>',           $close_window);
    $top->protocol('WM_DELETE_WINDOW',  $close_window);
    
    $top->bind('<Destroy>', sub{ $self = undef });
}

sub update_from_XaceSeqChooser {
    my( $self, $xc ) = @_;
    
    $self->query_Sequence($xc->get_CloneSeq->Sequence);
    $self->set_entry('genomic', $xc->slice_name);
    $self->update_from_clipboard;
    my $top = $self->top;
    $top->deiconify;
    $top->raise;
}

sub query_Sequence {
    my( $self, $query_Sequence ) = @_;
    
    if ($query_Sequence) {
        $self->{'_query_Sequence'} = $query_Sequence;
    }
    return $self->{'_query_Sequence'};
}

sub update_from_clipboard {
    my( $self ) = @_;
    
    if (my ($name, $start, $end) = $self->name_start_end_from_fMap_blue_box) {
        $self->set_entry('match', $name);
        my $flank = $self->get_entry('flank') || 0;
        $self->set_entry('genomic_start', $start - $flank);
        $self->set_entry('genomic_end',   $end   + $flank);
    }
}

sub set_entry {
    my( $self, $method, $txt ) = @_;
    
    my $entry = $self->$method();
    $entry->delete(0, 'end');
    $entry->insert(0, $txt);
}

sub get_entry {
    my( $self, $method ) = @_;
    
    my $txt = $self->$method()->get or return;
    $txt =~ s/\s//g;
    return $txt;
}

sub match {
    my( $self, $match ) = @_;
    
    if ($match) {
        $self->{'_match'} = $match;
    }
    return $self->{'_match'};
}

sub genomic {
    my( $self, $genomic ) = @_;
    
    if ($genomic) {
        $self->{'_genomic'} = $genomic;
    }
    return $self->{'_genomic'};
}

sub genomic_start {
    my( $self, $genomic_start ) = @_;
    
    if (defined $genomic_start) {
        $self->{'_genomic_start'} = $genomic_start;
    }
    return $self->{'_genomic_start'};
}

sub genomic_end {
    my( $self, $genomic_end ) = @_;
    
    if (defined $genomic_end) {
        $self->{'_genomic_end'} = $genomic_end;
    }
    return $self->{'_genomic_end'};
}

sub flank {
    my( $self, $flank ) = @_;
    
    if ($flank) {
        $self->{'_flank'} = $flank;
    }
    return $self->{'_flank'};
}

sub top {
    my( $self, $top ) = @_;
    
    if ($top) {
        $self->{'_top'} = $top;
    }
    return $self->{'_top'};
}

sub revcomp_ref {
    my( $self, $revcomp_ref ) = @_;
    
    if ($revcomp_ref) {
        $self->{'_revcomp_ref'} = $revcomp_ref;
    }
    return $self->{'_revcomp_ref'};
}

sub dotter {
    my( $self, $dotter ) = @_;
    
    if ($dotter) {
        $self->{'_dotter'} = $dotter;
    }
    return $self->{'_dotter'};
}

sub launch_dotter {
    my( $self ) = @_;
    
    my $match_name = $self->get_entry('match');
    my $start      = $self->get_entry('genomic_start');
    my $end        = $self->get_entry('genomic_end');
    my $genomic    = $self->query_Sequence;
    my $revcomp    = $self->revcomp_ref;
    
    unless ($match_name and $genomic and $start and $end and $genomic) {
        warn "Missing parameters\n";
        return;
    }
    
    my $length = $genomic->sequence_length;
    $start = 1       if $start < 1;
    $end   = $length if $end   > $length;
    
    my $dotter = $self->dotter;
    $dotter->query_Sequence($genomic);
    $dotter->query_start($start);
    $dotter->query_end($end);
    $dotter->subject_name($match_name);
    $dotter->revcomp_subject($$revcomp);
    
    return $dotter->fork_dotter;
}

sub name_start_end_from_fMap_blue_box {
    my( $self ) = @_;
    
    my $tk = $self->top;

    my( $text );
    eval {
        $text = $tk->SelectionGet;
    };
    return if $@;
    
    #warn "clipboard: $text";
    
    # Match fMap "blue box"
    if ($text =~ /^(?:<?(?:Protein|Sequence)[:>]?)?\"?([^\"\s]+)\"?\s+-?(\d+)\s+-?(\d+)\s+\(\d+\)/) {
        my $name  = $1;
        my $start = $2;
        my $end   = $3;
        ($start, $end) = ($end, $start) if $start > $end;
        #warn "Got ($name, $start, $end)";
        return ($name, $start, $end);
    } else {
        return;
    }
}

sub DESTROY {
    #warn "Freeing DotterWindow\n";
}

1;

__END__

=head1 NAME - CanvasWindow::DotterWindow

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

