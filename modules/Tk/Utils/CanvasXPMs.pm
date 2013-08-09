
### Tk::Utils::CanvasXPMs

package Tk::Utils::CanvasXPMs;

use strict;
use warnings;

sub arrow_right_xpm {
    my ($canvas) = @_;

    my $data = <<'END_OF_PIXMAP' ;
/* XPM */
static char * arrow_right[] = {
"13 13 2 1",
"     c None",
"+    c #778899",
"             ",
"  ++         ",
"  ++++       ",
"  +++++      ",
"  +++++++    ",
"  +++++++++  ",
"  ++++++++++ ",
"  +++++++++  ",
"  +++++++    ",
"  +++++      ",
"  ++++       ",
"  ++         ",
"             "};
END_OF_PIXMAP

    return $canvas->Pixmap( -data => $data );
}

sub arrow_right_active_xpm {
    my ($canvas) = @_;

    my $data = <<'END_OF_PIXMAP' ;
/* XPM */
static char * arrow_right_active[] = {
"13 13 2 1",
"     c None",
"+    c #2f4f4f",
"             ",
"  ++         ",
"  ++++       ",
"  +++++      ",
"  +++++++    ",
"  +++++++++  ",
"  ++++++++++ ",
"  +++++++++  ",
"  +++++++    ",
"  +++++      ",
"  ++++       ",
"  ++         ",
"             "};
END_OF_PIXMAP

    return $canvas->Pixmap( -data => $data );
}


sub arrow_down_xpm {
    my ($canvas) = @_;

    my $data = <<'END_OF_PIXMAP' ;
/* XPM */
static char * arrow_down[] = {
"13 13 2 1",
"     c None",
"+    c #778899",
"             ",
"             ",
" +++++++++++ ",
" +++++++++++ ",
"  +++++++++  ",
"  +++++++++  ",
"   +++++++   ",
"    +++++    ",
"    +++++    ",
"     +++     ",
"     +++     ",
"      +      ",
"             "};
END_OF_PIXMAP

    return $canvas->Pixmap( -data => $data );
}

sub arrow_down_active_xpm {
    my ($canvas) = @_;

    my $data = <<'END_OF_PIXMAP' ;
/* XPM */
static char * arrow_down_active[] = {
"13 13 2 1",
"     c None",
"+    c #2f4f4f",
"             ",
"             ",
" +++++++++++ ",
" +++++++++++ ",
"  +++++++++  ",
"  +++++++++  ",
"   +++++++   ",
"    +++++    ",
"    +++++    ",
"     +++     ",
"     +++     ",
"      +      ",
"             "};
END_OF_PIXMAP

    return $canvas->Pixmap( -data => $data );
}

sub off_checkbutton_xpm {
    my ($canvas) = @_;

        my $data = <<'END_OF_PIXMAP' ;
/* XPM */
static char * arrow_right[] = {
"13 13 4 1",
"     c None",
".    c #bebebe",
"+    c #cccccc",
"o    c #666666",
"             ",
" +++++++++++ ",
" +.........o ",
" +.........o ",
" +.........o ",
" +.........o ",
" +.........o ",
" +.........o ",
" +.........o ",
" +.........o ",
" +.........o ",
" +oooooooooo ",
"             "};
END_OF_PIXMAP

    return $canvas->Pixmap( -data => $data );    
}

sub on_checkbutton_xpm {
    my ($canvas) = @_;

        my $data = <<'END_OF_PIXMAP' ;
/* XPM */
static char * arrow_right[] = {
"13 13 4 1",
"     c None",
".    c gold",
"o    c #cccccc",
"+    c #666666",
"             ",
" +++++++++++ ",
" +.........o ",
" +.........o ",
" +.........o ",
" +.........o ",
" +.........o ",
" +.........o ",
" +.........o ",
" +.........o ",
" +.........o ",
" +oooooooooo ",
"             "};
END_OF_PIXMAP

    return $canvas->Pixmap( -data => $data );    
}


1;

__END__

=head1 NAME - Tk::Utils::CanvasXPMs

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

