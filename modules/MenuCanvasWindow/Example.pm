
### MenuCanvasWindow::Example

package MenuCanvasWindow::Example;

use strict;
use warnings;
use base 'MenuCanvasWindow';


sub initialize {
    my( $self ) = @_;
    
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

=head1 NAME - MenuCanvasWindow::Example

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

