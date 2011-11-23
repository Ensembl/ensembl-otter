
### MenuCanvasWindow

package MenuCanvasWindow;

use strict;
use warnings;
use Carp;
use base qw( CanvasWindow );

sub new {
    my( $pkg, $tk, @rest ) = @_;

    my $menu_frame = $tk->Frame(
        -borderwidth    => 1,
        -relief         => 'raised',
        );
    $menu_frame->pack(
        -side   => 'top',
        -fill   => 'x',
        );
    
    my $self = $pkg->SUPER::new($tk, @rest);
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

1;

__END__

=head1 NAME - MenuCanvasWindow

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

