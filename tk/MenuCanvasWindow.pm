
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

=head2 hash_from_clipboard

       Args: hash of arrays
             {key_name => [qr/(reg)(ex)/, array_index]...}
   Function: Parse the AceDB clipboard
Description: clipboard is split on space for the processing by supplied
             regular expressions. Arrays returned will be empty if no
             matches are found so a quick die unless @{$returned->{key_name}} 
             will check that a match was found.
     return: hash of arrays
             {key_name => [ 'reg', 'ex' ]}

=cut

sub hash_from_clipboard {
    my( $self, $regex_hash ) = @_;
    warn "please pass me a nice hash" unless $regex_hash;
    my $results = { map { $_ => 0 } keys %$regex_hash };

    my $canvas = $self->canvas;

    my( $text );
    eval {
        $text = $canvas->SelectionGet;
    };
    return if $@;
#    warn "Trying to parse: [$text]\n";

    my @s = split(/\s+/, $text);

    foreach my $k(keys(%$regex_hash)){
	my $regex = $regex_hash->{$k}->[0];
	my $index = $regex_hash->{$k}->[1];
	$results->{$k} = [ $s[$index] =~ $regex ] || [];
    }

    return $results;
}

1;

__END__

=head1 NAME - MenuCanvasWindow

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

