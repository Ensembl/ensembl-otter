
### CanvasWindow::MainWindow

package CanvasWindow::MainWindow;

use strict;

use vars '@ISA';
use Tk;

@ISA = ('MainWindow');

sub new {
    my( $pkg, $title ) = @_;
    
    $title ||= 'Canvas Window';
    
    my $mw = $pkg->SUPER::new(
        -class => 'CanvasWindow',
        -title => $title,
        #-colormap   => 'new',
        );
    $mw->configure(
        -background     => '#bebebe',
        );
    $mw->scaling(1);    # Sets 1 screen pixel = 1 point
    #warn "Scaling = ", $mw->scaling, "\n";
    
    $mw->read_custom_option_file;
    
    $mw->add_default_bindings;
    
    return $mw;
}

sub add_default_bindings {
    my( $mw ) = @_;
    
    my $exit = sub{ exit; };
    $mw->bind('<Control-q>', $exit);
    $mw->bind('<Control-Q>', $exit);
}

sub read_custom_option_file {
    my( $mw ) = @_;
    
    my $xres_file = (getpwuid($<))[7] . "/.CanvasWindow.Xres";
    my $no_file = 0;
    unless (-e $xres_file) {
        local *XRES;
        if (open XRES, "> $xres_file") {
            print XRES q{

CanvasWindow*background: #bebebe
CanvasWindow*TopLevel*background: #bebebe
CanvasWindow*troughColor: #aaaaaa
CanvasWindow*foreground: black
CanvasWindow*activecolor: #ffd700
CanvasWindow*color: #ffd700
CanvasWindow*Entry.borderWidth: 1
CanvasWindow*Button.borderWidth: 1
CanvasWindow*Scrollbar.borderWidth: 1
CanvasWindow*Scrollbar.width: 11
CanvasWindow*Menu.borderWidth: 1
CanvasWindow*font: -*-helvetica-medium-r-*-*-12-*-*-*-*-*-*-*

};
            close XRES;

        } else {
            $no_file = 1;
        }
    }
    $mw->optionReadfile($xres_file);
}

1;

__END__

=head1 NAME - CanvasWindow::MainWindow

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

