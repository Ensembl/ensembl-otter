=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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

package Tk::HeadedCanvas;

# a double-headed canvas with scrolls
#
# lg4

use strict;
use Tk;

use base ('Tk::DestroyReporter', 'Tk::Frame');

Construct Tk::Widget 'HeadedCanvas';

use Tk::Submethods (    # propagate xviewMoveto(@_) --> xview('moveto',@_); etc
    'xview' => [qw(moveto scroll)],
    'yview' => [qw(moveto scroll)],
);

sub Populate {
    my ($self, $args) = @_;

    $self->SUPER::Populate($args);

    # creation and packing of auxiliary frames:
    my $botframe = $self->Frame()->pack(-side => 'bottom', -fill => 'x');
    my $lframe   = $self->Frame()->pack(-side => 'left',   -fill => 'y');
    my $cframe   = $self->Frame()->pack(-side => 'left',   -fill => 'both', -expand => 1);

    # creation and packing of subwidgets:
    my $sh     = $botframe->Scrollbar(-orient => 'horizontal');
    my $sqsize = $sh->reqheight();
    my $minisq = $botframe->Frame(-width => $sqsize, -height => $sqsize)->pack(-in => $botframe, -side => 'right');
    $sh->pack(-side => 'left', -fill => 'x', -expand => 1);

    my $sv = $self->Scrollbar(-orient => 'vertical')->pack(-side => 'right', -fill => 'y');

    my $topleft_canvas = $lframe->Canvas(-width => 0, -height => 0)->pack(-side => 'top');
    my $left_canvas = $lframe->Canvas(-width => 0)->pack(-side => 'left', -fill => 'y', -expand => 1);
    my $top_canvas = $cframe->Canvas(-height => 0)->pack(-side => 'top', -fill => 'x');
    my $main_canvas = $cframe->Canvas()->pack(-side => 'bottom', -fill => 'both', -expand => 1);

    # scrolls' binding:
    $sh->configure(-command => [ $self => 'xview' ]);
    $top_canvas->configure(-xscrollcommand => [ $sh => 'set' ]);
    $main_canvas->configure(-xscrollcommand => [ $sh => 'set' ]);

    $sv->configure(-command => [ $self => 'yview' ]);
    $left_canvas->configure(-yscrollcommand => [ $sv => 'set' ]);
    $main_canvas->configure(-yscrollcommand => [ $sv => 'set' ]);

    # advertisement:
    $self->Advertise('main_canvas'    => $main_canvas);
    $self->Advertise('left_canvas'    => $left_canvas);
    $self->Advertise('top_canvas'     => $top_canvas);
    $self->Advertise('topleft_canvas' => $topleft_canvas);
    $self->Advertise('xscrollbar'     => $sh);
    $self->Advertise('yscrollbar'     => $sv);

    # delegate configuration to the main canvas:
    $self->ConfigSpecs(
        -background => [ [ 'DESCENDANTS', 'SELF' ], 'background', 'Background', 'white' ],
        -foreground => [ [ 'DESCENDANTS', 'SELF' ], 'foreground', 'Foreground', 'black' ],
        -scrollregion => [ 'METHOD', 'scrollregion', 'Scrollregion', [ 0, 0, 0, 0 ] ],
        'DEFAULT' => ['main_canvas'],
    );

    # delegate methods to the main canvas:
    $self->Delegates('DEFAULT' => 'main_canvas',);
}

sub canvases {
    my $self = shift @_;

    return [ map { $self->Subwidget($_); } ('main_canvas', 'left_canvas', 'top_canvas', 'topleft_canvas') ];
}

# overrriding the existing canvas methods:

sub delete {    # override the standard method
    my $self = shift @_;

    for my $c (@{ $self->canvases() }) {
        $c->delete(@_);
    }
}

sub scrollregion {
    my $self = shift @_;
    if (scalar(@_)) {    # configure request
        $self->fit_everything();
    }
    else {               # cget request
        return $self->Subwidget('main_canvas')->cget(-scrollregion);
    }
}

# calls to 'xview()' and 'yview()' should get propagated to the correct subcanvases:

sub xview {
    my $self = shift @_;

    if (!scalar(@_)) {
        return $self->Subwidget('main_canvas')->xview();
    }
    else {
        if (($_[0] eq 'moveto') && ($_[1] < 0)) {    # don't let it become negative
            $_[1] = 0;
        }
        foreach my $c ('main_canvas', 'top_canvas') {
            $self->Subwidget($c)->xview(@_);
        }
    }
}

sub yview {
    my $self = shift @_;

    if (!scalar(@_)) {
        return $self->Subwidget('main_canvas')->yview();
    }
    else {
        if (($_[0] eq 'moveto') && ($_[1] < 0)) {    # don't let it become negative
            $_[1] = 0;
        }
        foreach my $c ('main_canvas', 'left_canvas') {
            $self->Subwidget($c)->yview(@_);
        }
    }
}

sub defmin {    # not a method
    my ($def, $a, $b) = @_;

    return defined($a)
      ? (
        defined($b)
        ? (($a < $b) ? $a : $b)
        : $a
      )
      : (
        defined($b)
        ? $b
        : $def
      );
}

sub defmax {    # not a method
    my ($def, $a, $b) = @_;

    return defined($a)
      ? (
        defined($b)
        ? (($a > $b) ? $a : $b)
        : $a
      )
      : (
        defined($b)
        ? $b
        : $def
      );
}

sub fit_everything {
    my $self = shift @_;

    my ($m_x1,  $m_y1,  $m_x2,  $m_y2)  = $self->Subwidget('main_canvas')->bbox('all');
    my ($t_x1,  $t_y1,  $t_x2,  $t_y2)  = $self->Subwidget('top_canvas')->bbox('all');
    my ($l_x1,  $l_y1,  $l_x2,  $l_y2)  = $self->Subwidget('left_canvas')->bbox('all');
    my ($tl_x1, $tl_y1, $tl_x2, $tl_y2) = $self->Subwidget('topleft_canvas')->bbox('all');

    my $w_x1 = defmin(0, $tl_x1, $l_x1);
    my $w_x2 = defmax(0, $tl_x2, $l_x2);

    my $n_y1 = defmin(0, $tl_y1, $t_y1);
    my $n_y2 = defmax(0, $tl_y2, $t_y2);

    my $e_x1 = defmin(0, $t_x1, $m_x1);
    my $e_x2 = defmax(0, $t_x2, $m_x2);

    my $s_y1 = defmin(0, $l_y1, $m_y1);
    my $s_y2 = defmax(0, $l_y2, $m_y2);

    $self->Subwidget('topleft_canvas')->configure(
        -scrollregion => [ $w_x1, $n_y1, $w_x2, $n_y2 ],
        -width        => ($w_x2 - $w_x1),
        -height       => ($n_y2 - $n_y1),
    );

    $self->Subwidget('left_canvas')->configure(
        -scrollregion => [ $w_x1, $s_y1, $w_x2, $s_y2 ],
        -width        => ($w_x2 - $w_x1),
    );

    $self->Subwidget('top_canvas')->configure(
        -scrollregion => [ $e_x1, $n_y1, $e_x2, $n_y2 ],
        -height       => ($n_y2 - $n_y1),
    );

    $self->Subwidget('main_canvas')->configure(-scrollregion => [ $e_x1, $s_y1, $e_x2, $s_y2 ],);

    for my $c (@{ $self->canvases() }) {
        $c->xviewMoveto(0);
        $c->yviewMoveto(0);
    }
}

1;

