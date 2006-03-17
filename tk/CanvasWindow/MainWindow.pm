
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
    $mw->scaling(1);    # Sets 1 screen pixel = 1 point.
                        # This is important or text and objects print
                        # in different proportions from the Canvas
                        # compared to their appearance on screen.
    
    if (@command_line) {
        $mw->command([@command_line]);
        #$mw->protocol('WM_SAVE_YOURSELF', sub{ warn "Saving myself..."; sleep 2; $mw->destroy });
        $mw->protocol('WM_SAVE_YOURSELF', "");
    }
    
    #warn "Scaling = ", $mw->scaling, "\n";
    
    $mw->add_default_options;
    
    $mw->add_default_bindings;
    
    return $mw;
}

sub add_default_bindings {
    my( $mw ) = @_;
    
    my $exit = sub{ exit; };
    $mw->bind('<Control-q>', $exit);
    $mw->bind('<Control-Q>', $exit);
}

sub add_default_options {
    my ($mw) = @_;
    
    # Get warnings about "possible comments in qw"
    no warnings "qw";
    
    # Priority level of 40 is equivalent to an
    # application specific startup file.
    my $priority = 40;
    my @opt_val = qw{
        CanvasWindow*color                      #ffd700
        CanvasWindow*background                 #bebebe
        CanvasWindow*foreground                 black
        CanvasWindow*selectBackground           gold
        CanvasWindow*selectColor                gold
        CanvasWindow*activeBackground           #dfdfdf
        CanvasWindow*troughColor                #aaaaaa
        CanvasWindow*activecolor                #ffd700
        CanvasWindow*borderWidth                1
        CanvasWindow*activeborderWidth          1
        CanvasWindow*font                       -*-helvetica-medium-r-*-*-12-*-*-*-*-*-*-*

        CanvasWindow*TopLevel*background        #bebebe
        CanvasWindow*Frame.borderWidth          0
        CanvasWindow*Scrollbar.width            11
        CanvasWindow*Menubutton.padX            6
        CanvasWindow*Menubutton.padY            6
    };
    
    for (my $i = 0; $i < @opt_val; $i += 2) {
        my ($opt, $val) = @opt_val[$i, $i + 1];
        #warn "Adding '$opt' : '$val'\n";
        $mw->optionAdd($opt, $val, $priority);
    }
    
    my @entry_class = qw{ Entry NoPasteEntry };
    foreach my $class (@entry_class) {
        $mw->optionAdd("CanvasWindow\*$class.relief",     'sunken', $priority);
        $mw->optionAdd("CanvasWindow\*$class.foreground", 'black',  $priority);
        $mw->optionAdd("CanvasWindow\*$class.background", 'white',  $priority);
    }
    
    # lucidatypewriter size 15 on dec_osf looks the same as size 14 on other systems
    my $font_size = $^O eq 'dec_osf' ? 15 : 14;
    foreach my $class (@entry_class) {
        $mw->optionAdd(
            "CanvasWindow\*$class.font",
            "-*-lucidatypewriter-medium-r-*-*-$font_size-*-*-*-*-*-*-*",
            $priority);
    }
}


1;

__END__

=head1 NAME - CanvasWindow::MainWindow

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

