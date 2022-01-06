=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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

