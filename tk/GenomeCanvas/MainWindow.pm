
### GenomeCanvas::MainWindow

package GenomeCanvas::MainWindow;

use strict;
use vars '@ISA';
use Tk;

@ISA = ('MainWindow');

sub new {
    my( $pkg, $title ) = @_;
    
    $title ||= 'Genome Canvas';
    
    my $mw = $pkg->SUPER::new(
        -class => 'GenomeCanvas',
        -title => $title,
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
    
    my $xres_file = (getpwuid($<))[7] . "/.GenomeCanvas.Xres";
    my $no_file = 0;
    unless (-e $xres_file) {
        local *XRES;
        if (open XRES, "> $xres_file") {
            print XRES q{

GenomeCanvas*background: #bebebe
GenomeCanvas*TopLevel*background: #bebebe
GenomeCanvas*troughColor: #aaaaaa
GenomeCanvas*foreground: black
GenomeCanvas*activecolor: #ffd700
GenomeCanvas*color: #ffd700
GenomeCanvas*Entry.borderWidth: 1
GenomeCanvas*Button.borderWidth: 1
GenomeCanvas*Scrollbar.borderWidth: 1
GenomeCanvas*Scrollbar.width: 11
GenomeCanvas*Menu.borderWidth: 1
GenomeCanvas*font: -*-helvetica-medium-r-*-*-12-*-*-*-*-*-*-*

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

=head1 NAME - GenomeCanvas::MainWindow

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

