
### ExonCanvas

package ExonCanvas;

use strict;
use Carp;
use CanvasWindow;
use vars ('@ISA');

@ISA = ('CanvasWindow');

sub add_ace_subseq {
    my( $self, $subseq, $x_offset ) = @_;
    
    $x_offset ||= 0;
    
    my $expected_class = 'Hum::Ace::SubSeq';
    unless ($subseq->isa($expected_class)) {
        warn "Unexpected object '$subseq', expected a '$expected_class'";
    }
    
    # Get the offset underneath everthing else
    my $y_offset = ($self->canvas->bbox('all'))[3];
    
    my $strand = $subseq->strand;
    foreach my $ex ($subseq->get_all_Exons) {
        $y_offset += $self->add_exon_holder($ex, $strand, $x_offset, $y_offset);
    }
}

sub add_exon_holder {
    my( $self, $exon, $strand, $x_offset, $y_offset ) = @_;
    
    my $canvas  =          $self->canvas;
    my $font    =          $self->font;
    my $size    =          $self->font_size;
    my $exon_id = 'exon-'. $self->next_exon_number;
    my $pad  = int($size / 6);
    my $half = int($size / 2);
    my $arrow_size = $half - $pad;
    $y_offset += $half + $pad;
    
    my $line_length = $size;
    
    my $arrow = ($strand == 1) ? 'last' : 'first';
    
    my $start_text = $canvas->createText(
        $x_offset - $size, $y_offset,
        -anchor     => 'e',
        -justify    => 'right',
        -text       => $exon->start,
        -font       => [$font, $size, 'normal'],
        -tags       => [$exon_id],
        );
    
    my $strand_arrow = $canvas->createLine(
        $x_offset - $half, $y_offset,
        $x_offset + $half, $y_offset,
        -width      => 1,
        -arrow      => $arrow,
        -arrowshape => [$arrow_size, $arrow_size, $arrow_size - $pad],
        -tags       => [$exon_id],
        );
    
    my $end_text = $canvas->createText(
        $x_offset + $size, $y_offset,
        -anchor     => 'w',
        -justify    => 'left',
        -text       => $exon->end,
        -font       => [$font, $size, 'normal'],
        -tags       => [$exon_id],
        );
    
    $self->record_exon_inf($exon_id, $start_text, $strand_arrow, $end_text);
    
    # Return how big we were
    return $size + $pad;
}

sub record_exon_inf {
    my( $self, $exon_id, @inf ) = @_;
    
    $self->{'_exons'}{$exon_id} = [@inf];
}

sub to_ace_subseq {
    my( $self ) = @_;
    
    my $e = $self->{'_exons'};
    my $canvas = $self->canvas;
    
    my $subseq = Ace::SubSeq->new;
    $subseq->name($canvas->TopLevel->cget('title'));

    my( $subseq_strand );
    foreach my $exid (keys %$e) {
        my ($start_id, $strand_arrow, $end_id) = @{$e->{$exid}};
        
        my $start  =  $canvas->itemcget($start_id, 'text');
        my $strand = ($canvas->itemcget($strand_arrow, 'arrow') eq 'last') ? 1 : -1;
        my $end    =  $canvas->itemcget(  $end_id, 'text');
        
        if ($subseq_strand) {
            $self->message("inconsistent strands")
                unless $strand == $subseq_strand;
        } else {
            $subseq_strand = $strand;
        }
        
        my $exon = Hum::Ace::Exon->new;
        $exon->start($start);
        $exon->end($end);
        
        $subseq->add_Exon($exon);
    }
    $subseq->strand($subseq_strand);
    
    return $subseq;
}

sub message {
    my( $self, @message ) = @_;
    
    # put in stuff to put message in window
    print STDERR "\n", @message, "\n";
}

sub max_exon_number {
    my( $self ) = @_;
    
    return $self->{'_max_exon_number'} || 0;
}

sub next_exon_number {
    my( $self ) = @_;
    
    $self->{'_max_exon_number'}++;
    return $self->{'_max_exon_number'};
}

sub font {
    my( $self, $font ) = @_;
    
    if ($font) {
        $self->{'_font'} = $font;
    }
    return $self->{'_font'} || 'lucidatypewriter';
}

sub font_size {
    my( $self, $font_size ) = @_;
    
    if ($font_size) {
        $self->{'_font_size'} = $font_size;
    }
    return $self->{'_font_size'} || 15;
}

1;

__END__

=head1 NAME - ExonCanvas

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

