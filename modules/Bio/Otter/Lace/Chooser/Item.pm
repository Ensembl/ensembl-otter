=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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


### Bio::Otter::Lace::Chooser::Item

package Bio::Otter::Lace::Chooser::Item;

use strict;
use warnings;
use Carp;

sub new {
    my ($pkg) = @_;

    return bless {}, $pkg;
}

sub string {
    confess "string() not implemented in ", ref(shift);
}

sub is_Bracket {
    confess "is_Bracket() not implemented in ", ref(shift);
}

sub indent {
    my ($self, $indent) = @_;

    if (defined $indent) {
        $self->{'_indent'} = $indent;
    }
    return $self->{'_indent'};
}

sub name {
    my ($self, $name) = @_;

    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub selected {
    my($self, $flag) = @_;

    if (defined $flag) {
        $self->{'_selected'} = $flag ? 1 : 0;
    }
    return $self->{'_selected'};
}

sub disabled {
    my($self, $flag) = @_;

    if (defined $flag) {
        $self->{'_disabled'} = $flag ? 1 : 0;
    }
    return $self->{'_disabled'};
}


1;

__END__

=head1 NAME - Bio::Otter::Lace::Chooser::Item

=head1 DESCRIPTION

Base class for item data objects drawn in the ColumnChooser window.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

