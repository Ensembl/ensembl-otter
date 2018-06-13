=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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


### GenomeCanvas::DensityBand::RepeatFeature

package GenomeCanvas::DensityBand::RepeatFeature;

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
        @classes = qw{ SINE LINE LTR DNA };
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
    if (0) {
        # Don't know if we need this code any more now that we don't
        # create bitmaps.
        while (my($vc, $x_offset) = $band->next_sub_VirtualContig) {
            $band->draw_repeat_features_on_sub_vc($vc, $x_offset);
        }
    } else {
        my $vc = $band->virtual_contig;
        $band->draw_repeat_features_on_sub_vc($vc, 0);
    }
}

sub draw_repeat_features_on_sub_vc {
    my( $band, $vc, $x_offset ) = @_;

    my $repeat_classifier = $band->repeat_classifier;
    my @class_list = $band->repeat_classes;
    my $other_class = $class_list[$#class_list];
    my %class = map {$_, []} @class_list;

    my $pipe_vc = $band->LaceSlice_from_vc($vc);
    foreach my $r (@{$pipe_vc->get_all_RepeatFeatures('RepeatMasker', 1)}) {
        my $c = &$repeat_classifier($band, $r) || $other_class;
	    if (defined $c) {
	        push @{$class{$c}}, $r;
	    }
    }
    
    my $vc_length = $vc->length;
    for (my $i = 0; $i < @class_list; $i++) {
        my $c = $class_list[$i];
        $band->draw_density_segment($x_offset, $i, $vc_length, @{$class{$c}});
    }
}

1;

__END__

=head1 NAME - GenomeCanvas::DensityBand::RepeatFeature

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

