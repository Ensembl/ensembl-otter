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


### EditWindow

package EditWindow;

use strict;
use warnings;

use Try::Tiny;

use parent 'BaseWindow';


sub new {
    my ($pkg, $tk) = @_;

    my $self = bless {}, $pkg;
    $self->top($tk);
    return $self;
}

sub top {
    my ($self, $top) = @_;

    if ($top) {
        $self->{'_top'} = $top;
    }
    return $self->{'_top'};
}

sub colour_init {
    my ($self, @widg) = @_;
    my $sw = $self->can('SessionWindow') && $self->SessionWindow;
    if ($sw) {
        $sw->colour_init($self->top, @widg);
    } else {
        # some just don't, but they should not call
        die "$self uncoloured, no SessionWindow (yet?)";
    }
    return;
}

sub set_minsize {
    my ($self) = @_;

    my $top = $self->top;
    $top->update;
    $top->minsize($top->width, $top->height);
    return;
}

sub get_clipboard_text {
    my ($self) = @_;

    my $top = $self->top;
    return unless Tk::Exists($top);

    return try {
        return $top->SelectionGet(
            -selection => 'PRIMARY',
            -type      => 'STRING',
            );
    };
}

1;

__END__

=head1 NAME - EditWindow

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

