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


package Bio::Otter::UI::TextWindow::TranscriptAlign;

use 5.012;

use strict;
use warnings;

use Bio::Otter::Lace::Client;

use parent 'Bio::Otter::UI::TextWindow';

sub new {
    my ($pkg, $parent, $type) = @_;
    my $self = $pkg->SUPER::new($parent);

    $self->type($type);

    return $self;
}

sub buttons {
    my ($self, $frame, $top) = @_;

    my $close_command = sub{ $top->withdraw; $self->parent->delete_alignment_window($self->type) };
    $self->window->bind('<Destroy>', $close_command);

    return $close_command;
}

sub update_alignment {
    my ($self, $alignment) = @_;
    my $window = $self->window;

    # Empty the text widget
    $window->delete('1.0', 'end');
    $window->insert('end', $alignment); # just show it raw for now

    $self->size_widget;

    my $toplevel = $window->toplevel;

    # Set the window title
    $toplevel->configure( -title => sprintf('%s%s alignment',
                                            $Bio::Otter::Lace::Client::PFX,
                                            $self->type) );

    $toplevel->deiconify;
    $toplevel->raise;

    return;
}

sub width {
    return 80;
}

sub type {
    my ($self, $type) = @_;
    if ($type) {
        $self->{'_type'} = $type;
    }
    return $self->{'_type'};
}

1;

__END__

=head1 NAME - Bio::Otter::UI::TextWindow::TranscriptAlign

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
