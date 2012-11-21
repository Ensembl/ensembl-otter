
### CanvasWindow::Utils

package CanvasWindow::Utils;

use strict;
use warnings;

use base qw( Exporter );
use vars qw ( @EXPORT_OK );

@EXPORT_OK = qw{
    expand_bbox
    };

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

