
### MenuCanvasWindow

package MenuCanvasWindow;

use strict;
use Carp;
use CanvasWindow;
use vars '@ISA';

@ISA = ('CanvasWindow');

sub new {
    my( $pkg, $tk ) = @_;

    my $menu_frame = $tk->Frame(
        -borderwidth    => 1,
        -relief         => 'raised',
        );
    $menu_frame->pack(
        -side   => 'top',
        -fill   => 'x',
        );
    
    my $self = $pkg->SUPER::new($tk);
    $self->menu_bar($menu_frame);
    return $self;
}

sub menu_bar {
    my( $self, $bf ) = @_;
    
    if ($bf) {
        $self->{'_menu_bar'} = $bf;
    }
    return $self->{'_menu_bar'};
}


sub make_menu {
    my( $self, $name, $pos ) = @_;
    
    $pos ||= 0;
    
    my $menu_frame = $self->menu_bar
        or confess "No menu_bar";
    my $button = $menu_frame->Menubutton(
        -text       => $name,
        -underline  => $pos,
        #-padx       => 8,
        #-pady       => 6,
        );
    $button->pack(
        -side       => 'left',
        );
    my $menu = $button->Menu(
        -tearoff    => 0,
        );
    $button->configure(
        -menu       => $menu,
        );
    return $menu;
}

sub integers_from_clipboard {
    my( $self ) = @_;

    my $canvas = $self->canvas;

    my( $text );
    eval {
        $text = $canvas->SelectionGet;
    };
    return if $@;
    #warn "Trying to parse: [$text]\n";
    
    my( @ints );
    # match fMap "blue box" DNA selection
    if (@ints = $text =~ /Selection -?(\d+) ---> -?(\d+)/) {
        if ($ints[0] == $ints[1]) {
            # user clicked on single base pair
            @ints = ($ints[0]);
        }
    } else {
        # match general fMap "blue box" pattern
        unless (@ints = $text =~ /^\S+\s+-?(\d+)\s+-?(\d+)\s+\(\d+\)/) {
            # or just get all the integers
            @ints = grep ! /\./, $text =~ /([\.\d]+)/g;
        }
    }
    return @ints;
}


1;

__END__

=head1 NAME - MenuCanvasWindow

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

