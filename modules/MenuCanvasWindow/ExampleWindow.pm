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


### MenuCanvasWindow::ExampleWindow

package MenuCanvasWindow::ExampleWindow;

use strict;
use warnings;
use base 'MenuCanvasWindow';


sub initialise {
    my ($self) = @_;

    my $file_menu = $self->make_menu('File');
    $file_menu->add('command',
        -label          => 'New',
        -command        => sub { print "new\n" },
        -accelerator    => 'Ctrl+N',
        -underline      => 1,
        );    

    return;
}


1;

__END__

=head1 NAME - MenuCanvasWindow::ExampleWindow

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

