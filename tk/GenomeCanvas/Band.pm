
### GenomeCanvas::Band

package GenomeCanvas::Band;

use strict;
use Carp;
use GenomeCanvas::State;

use vars '@ISA';
@ISA = ('GenomeCanvas::State');

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub tags {
    my( $band, @tags ) = @_;
    
    if (@tags) {
        $band->{'_tags'} = [@tags];
    }
    if (my $tags = $band->{'_tags'}) {
        return @$tags;
    } else {
        return;
    }
}

sub render {
    my( $band ) = @_;
    
    my $color = 'red';
    warn "GenomeCanvas::Band : Drawing default $color rectangle\n";

    my $canvas   = $band->canvas;
    my $y_offset = $band->y_offset;
    my @tags     = $band->tags;

    my @bbox = $canvas->bbox;
    my( $width );
    if (@bbox) {
        $width = $bbox[2] - $bbox[0];
    } else {
        $width = 600;
    }
    
    my @rect = (0, $y_offset, $width, $y_offset + 10);
    my $id = $canvas->createRectangle(
        @rect,
        -fill       => $color,
        -outline    => undef,
        '-tags'     => [@tags],
        );
}

sub tick_label {
    my( $band, $text, $dir, @line_start ) = @_;
    
    my @tags = $band->tags;
    confess "line_start array must have 2 elements" unless @line_start == 2;
    
    my $tick_length = 4;
    my $label_pad   = 3;
    my( $anchor, $justify, @line_end, @text_start );
    if ($dir eq 'n') {
        $anchor = 's';
        $justify = 'center';
        @line_end = ($line_start[0], $line_start[1] - $tick_length);
        @text_start = ($line_end[0], $line_end[1]   - $label_pad);
    }
    elsif ($dir eq 'e') {
        $anchor = 'w';
        $justify = 'left';
        @line_end = ($line_start[0] + $tick_length, $line_start[1]);
        @text_start = ($line_end[0] + $label_pad,   $line_end[1]);
    }
    elsif ($dir eq 's') {
        $anchor = 'n';
        $justify = 'center';
        @line_end = ($line_start[0], $line_start[1] + $tick_length);
        @text_start = ($line_end[0], $line_end[1]   + $label_pad);
    }
    elsif ($dir eq 'w') {
        $anchor = 'e';
        $justify = 'right';
        @line_end = ($line_start[0] - $tick_length, $line_start[1]);
        @text_start = ($line_end[0] - $label_pad,   $line_end[1]);
    }
    else {
        confess "unknown direction '$dir'";
    }
    
    my $canvas = $band->canvas;
    $canvas->createLine(
        @line_start, @line_end,
        '-tags'     => [@tags],
        );
    $canvas->createText(
        @text_start,
        -text       => $text,
        -anchor     => $anchor,
        -justify    => $justify,
        '-tags'     => [@tags],
        );
}

sub virtual_contig {
    my( $band, $vc ) = @_;
    
    if ($vc) {
        confess "Not a Bio::EnsEMBL::Virtual::Contig : '$vc'"
            unless ref($vc) and $vc->isa('Bio::EnsEMBL::Virtual::Contig');
        $band->{'_virtual_contig'} = $vc;
    }
    return $band->{'_virtual_contig'};
}

sub nudge_into_free_space {
    my( $band, $tag_or_id, $y_inc ) = @_;
    
    confess "No tagOrId" unless $tag_or_id;
    $y_inc ||= 10;
    
    my $canvas = $band->canvas;
    my %self = map {$_, 1} $canvas->find('withtag', $tag_or_id);
    while (grep ! $self{$_}, $canvas->find('overlapping', $canvas->bbox($tag_or_id))) {
        $canvas->move($tag_or_id, 0, $y_inc);
    }
}

sub width {
    my( $band ) = @_;
    
    my $vc = $band->virtual_contig
        or confess "No virtual contig attached";
    my $seq_length = $vc->length;
    my $rpp = $band->residues_per_pixel;
    return $seq_length / $rpp;
}

sub y_max {
    my( $band ) = @_;
    
    my $y_offset = $band->y_offset;
    my $height = $band->height;
    return $y_offset + $height;
}

1;

__END__

=head1 NAME - GenomeCanvas::Band

=head1 DESCRIPTION

Base class for GenomeCanvas band objects.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

