
### GenomeCanvas::Band

package GenomeCanvas::Band;

use strict;
use Carp;
use GenomeCanvas::State;

use vars '@ISA';
@ISA = 'GenomeCanvas::State';

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub render {
    my( $band ) = @_;
    
    warn "GenomeCanvas::Band : Using default drawing method\n";
    my @bbox = $band->frame;
    my $width = ($bbox[2] - $bbox[0]) || 600;
    $bbox[1] = $bbox[3] + 3;
    $bbox[2] = $bbox[0] + $width;
    $bbox[3] = $bbox[1] + 4;
    
    my $canvas = $band->canvas;
    my $id = $canvas->createRectangle(@bbox,
        -fill => 'red',
        -tags => ["$band"],
        );
    
    $band->expand_frame(@bbox);
    #$band->nudge_into_free_space($id);
}

sub nudge_into_free_space {
    my( $band, $tag_or_id, $x_inc ) = @_;
    
    confess "No tagOrId" unless $tag_or_id;
    $x_inc ||= 10;
    
    my $canvas = $band->canvas;
    my %self = map {$_, 1} $canvas->find('withtag', $tag_or_id);
    while (grep ! $self{$_}, $canvas->find('overlapping', $canvas->bbox($tag_or_id))) {
        $canvas->move($tag_or_id, 0, $x_inc);
    }
}


1;

__END__

=head1 NAME - GenomeCanvas::Band

=head1 DESCRIPTION

Base class for GenomeCanvas band objects.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

