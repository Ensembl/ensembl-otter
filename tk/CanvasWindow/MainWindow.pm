
### CanvasWindow::MainWindow

package CanvasWindow::MainWindow;

use strict;

use vars '@ISA';
use Tk;

@ISA = ('MainWindow');

sub new {
    my( $pkg, $title, @command_line ) = @_;
    
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
    
    if (@command_line) {
        $mw->command([@command_line]);
        #$mw->protocol('WM_SAVE_YOURSELF', sub{ warn "Saving myself..."; sleep 2; $mw->destroy });
        $mw->protocol('WM_SAVE_YOURSELF', "");
    }
    
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
    my $mtime = (stat($xres_file))[9] || 0;

    ### Change time int here if you modify the X resources
    if ($mtime < 1066664026) {
        warn "Writing new X resource file '$xres_file'\n";
        rename($xres_file, "$xres_file.bak") if $mtime;

        local *XRES;
        if (open XRES, "> $xres_file") {
            print XRES q{

CanvasWindow*color: #ffd700
CanvasWindow*background: #bebebe
CanvasWindow*foreground: black
CanvasWindow*selectBackground: gold
CanvasWindow*selectColor: gold
CanvasWindow*activeBackground: #dfdfdf
CanvasWindow*troughColor: #aaaaaa
CanvasWindow*activecolor: #ffd700
CanvasWindow*borderWidth: 1
CanvasWindow*activeborderWidth: 1
CanvasWindow*font: -*-helvetica-medium-r-*-*-12-*-*-*-*-*-*-*

CanvasWindow*TopLevel*background: #bebebe
CanvasWindow*Frame.borderWidth: 0
CanvasWindow*Scrollbar.width: 11
CanvasWindow*Menubutton.padX: 6
CanvasWindow*Menubutton.padY: 6
CanvasWindow*Entry.relief: flat
CanvasWindow*Entry.font: -*-lucidatypewriter-medium-r-*-*-14-*-*-*-*-*-*-*
CanvasWindow*Entry.foreground: black
CanvasWindow*Entry.background: white

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

