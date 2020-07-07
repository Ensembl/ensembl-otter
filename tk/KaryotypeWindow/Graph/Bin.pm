=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

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


### KaryotypeWindow::Graph::Bin

package KaryotypeWindow::Graph::Bin;

use strict;
use warnings;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub start {
    my( $self, $start ) = @_;
    
    if ($start) {
        $self->{'_start'} = $start;
    }
    return $self->{'_start'};
}

sub end {
    my( $self, $end ) = @_;
    
    if ($end) {
        $self->{'_end'} = $end;
    }
    return $self->{'_end'};
}

sub value {
    my( $self, $value ) = @_;
    
    if ($value) {
        $self->{'_value'} = $value;
    }
    return $self->{'_value'};
}


1;

__END__

=head1 NAME - KaryotypeWindow::Graph::Bin

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

