
### XaceSeqChooser

package XaceSeqChooser;

use strict;
use Carp;
use CanvasWindow;
use vars ('@ISA');
use Hum::Ace;

@ISA = ('CanvasWindow');

sub new {
    my( $pkg, $tk ) = @_;
    
    my $button_frame = $tk->Frame;
    $button_frame->pack(
        -side   => 'top',
        -fill   => 'x',
        );
    my $self = $pkg->SUPER::new($tk);
    $self->button_frame($button_frame);
    $self->add_buttons;
    return $self;
}

sub button_frame {
    my( $self, $bf ) = @_;
    
    if ($bf) {
        $self->{'_button_frame'} = $bf;
    }
    return $self->{'_button_frame'};
}

sub add_buttons {
    my( $self, $tk ) = @_;
    
    my $bf = $self->button_frame;
    my $button = $bf->Button(
        -text       => 'xace',
        -command    => sub{
            $self->get_xace_window_id;
            });
    $button->pack(
        -side   => 'left',
        );
            
}

sub ace_handle {
    my( $self, $adbh ) = @_;
    
    if ($adbh) {
        $self->{'_ace_database_handle'} = $adbh;
    }
    return $self->{'_ace_database_handle'}
        || confess "ace_handle not set";
}

sub max_seq_list_length {
    return 100;
}

sub list_genome_sequences {
    my( $self, $offset ) = @_;
    
    $offset ||= 0;
    
    my $adbh = $self->ace_handle;
    my $length = $self->max_seq_list_length;
    my @gen_seq_list = map $_->name,
        $self->fetch(GenomeSequence => '*');
    my $total = @gen_seq_list;
    my $end = $offset + $length - 1;
    $end = $length - 1 if $end > $length;
    return($total, @gen_seq_list[$offset..$end]);
}

sub sequence_list {
    my( $self, @sequences ) = @_;
    
    if (@sequences) {
        $self->{'_sequence_list'} = [@sequences];
    }
    if (my $slist = $self->{'_sequence_list'}) {
        return @$slist;
    } else {
        return;
    }
}

sub draw_sequence_list {
    my( $self ) = @_;
    
    my @slist = $self->sequence_list;
    unless (@slist) {
        @slist = $self->list_genome_sequences;
    }
    for (my $i = 0; $i < @slist; $i++) {
        my $text = $slist[$i];
        
    }
}

sub xace_window_id {
    my( $self, $xwid ) = @_;
    
    if ($xwid) {
        $self->{'_xace_window_id'} = $xwid;
    }
    unless ($xwid = $self->{'_xace_window_id'}) {
        my $xwid = $self->get_xace_window_id;
        $self->{'_xace_window_id'} = $xwid;
    }
    return $xwid;
}

sub get_xace_window_id {
    my( $self ) = @_;
    
    $self->message("Please click on the xace main window with the cross-hairs");
    local *XWID;
    open XWID, "xwininfo |"
        or confess "Can't open pipe from xwininfo : $!";
    my( $xwid );
    while (<XWID>) {
        # xwininfo: Window id: 0x7c00026 "ACEDB 4_9c, lace bA314N13"
        if (/Window id: (\w+)/) {
            $xwid = $1;
        }
    }
    close XWID or confess "Error running xwininfo : $!";
    confess "No xace window id" unless $xwid;
    return $xwid;
}

sub message {
    my( $self, @message ) = @_;
    
    print STDERR "\n", @message, "\n";
}

1;

__END__

=head1 NAME - XaceSeqChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

