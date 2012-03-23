
### CanvasWindow::Utils

package CanvasWindow::Utils;

use strict;
use warnings;

use base qw( Exporter );
use vars qw ( @EXPORT_OK );

@EXPORT_OK = qw{
    bbox_union
    expand_bbox
    };

sub bbox_union {
    my ($bb1, $bb2) = @_;

    my @new = @$bb1;
    $new[0] = $bb2->[0] if $bb2->[0] < $bb1->[0];
    $new[1] = $bb2->[1] if $bb2->[1] < $bb1->[1];
    $new[2] = $bb2->[2] if $bb2->[2] > $bb1->[2];
    $new[3] = $bb2->[3] if $bb2->[3] > $bb1->[3];
    return @new;
}

sub expand_bbox {
    my ($bbox, $pad) = @_;

    $bbox->[0] -= $pad;
    $bbox->[1] -= $pad;
    $bbox->[2] += $pad;
    $bbox->[3] += $pad;

    return;
}


1;

__END__

=head1 NAME - CanvasWindow::Utils

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

