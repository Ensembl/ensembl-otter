
### GenomeCanvas::Band::RepeatFeature

package GenomeCanvas::Band::RepeatFeature;

use strict;
use Carp;
use GenomeCanvas::DensityBand;

use vars '@ISA';
@ISA = ('GenomeCanvas::DensityBand');

sub render {
    my( $band ) = @_;
    
    $band->draw_repeat_features;
    $band->draw_sequence_gaps;
    $band->draw_outline_and_labels;
}

sub repeat_classes {
    my( $band, @classes ) = @_;
    
    if (@classes) {
        $band->{'_repeat_classes'} = [@classes];
    }
    if (my $c = $band->{'_repeat_classes'}) {
        @classes = @$c;
    } else {
        @classes = qw{ SINE LINE DNA LTR };
    }
    push(@classes, 'Other');
    return @classes;
}

sub repeat_classifier {
    my( $band, $sub ) = @_;
    
    if ($sub) {
        confess "Not a subroutine ref: '$sub'"
            unless ref($sub) eq 'CODE';
        $band->{'_repeat_classifer'} = $sub;
    }
    return $band->{'_repeat_classifer'} || confess "No repeat classifer";
}

sub draw_repeat_features {
    my( $band ) = @_;
    
    $band->strip_labels($band->repeat_classes);
    while (my($vc, $x_offset) = $band->next_sub_VirtualContig) {
        $band->draw_repeat_features_on_sub_vc($vc, $x_offset);
    }
}

sub draw_repeat_features_on_sub_vc {
    my( $band, $vc, $x_offset ) = @_;

    my $repeat_classifier = $band->repeat_classifier;
    my @class_list = $band->repeat_classes;
    my $other_class = $class_list[$#class_list];
    my %class = map {$_, []} @class_list;
    foreach my $r ($vc->get_all_RepeatFeatures) {
        my $c = &$repeat_classifier($band, $r->hseqname) || $other_class;
        push @{$class{$c}}, $r;
    }
    
    my $vc_length = $vc->length;
    for (my $i = 0; $i < @class_list; $i++) {
        my $c = $class_list[$i];
        $band->draw_density_segment($x_offset, $i, $vc_length, @{$class{$c}});
    }
}

1;

__END__

=head1 NAME - GenomeCanvas::Band::RepeatFeature

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

