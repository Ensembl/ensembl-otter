
### CanvasWindow::ColumnChooser

package CanvasWindow::ColumnChooser;

use strict;
use warnings;
use Bio::Otter::Lace::Source::Collection;
use Bio::Otter::Lace::Source::SearchHistory;
use Tk::Utils::CanvasXPMs;

use base 'MenuCanvasWindow';

sub new {
    my ($pkg, $tk, @rest) = @_;

    # Need to make both frames which appear above the canvas...
    my $menu_frame = $pkg->make_menu_widget($tk);
    my $top_frame = $tk->Frame->pack(
        -side => 'top',
        -fill => 'x',
        );
    
    # ... before we make the canvas
    my $self = CanvasWindow->new($tk, @rest);
    bless($self, $pkg);

    $self->menu_bar($menu_frame);
    $self->top_frame($top_frame);
    return $self;
}

sub top_frame {
    my ($self, $top_frame) = @_;
    
    if ($top_frame) {
        $self->{'_top_frame'} = $top_frame;
    }
    return $self->{'_top_frame'};
}

sub row_height {
    my ($self) = @_;

    return int 1.5 * $self->font_size;
}

sub initialise {
    my ($self, $cllctn) = @_;

    my $search_menu = $self->make_menu('Search');
    my $view_menu = $self->make_menu('View');

    $self->font_size(12);

    my $hist = Bio::Otter::Lace::Source::SearchHistory->new($cllctn);
    $self->SearchHistory($hist);

    my $top = $self->top_window;
    my $top_frame = $self->top_frame;
    my @packing = qw{ -side top -fill x -expand 1 -padx 4 -pady 4 };
    my $snail_frame  = $top_frame->Frame->pack(@packing);
    my $search_frame = $top_frame->Frame->pack(@packing);

    $self->{'_snail_trail_frame'} = $snail_frame;
    $snail_frame->Label(
        -text => 'Filter trail: ',
        -padx => 4,
        -pady => 4,
        )->pack(-side => 'left');

    my $entry = $self->{'_search_Entry'} = $search_frame->Entry(
        -width        => 60,
        -textvariable => \$self->{'_entry_search_string'},
    )->pack(-side => 'left', -padx => 4);
    $self->set_search_entry($cllctn->search_string);

    my $filter = sub{ $self->do_filter };
    $search_frame->Button(-text => 'Filter', -command => $filter)->pack(-side => 'left', -padx => 4);

    my $back = sub{ $self->go_back };
    $search_frame->Button(-text => 'Back', -command => $back)->pack(-side => 'left', -padx => 4);

    $search_menu->add('command',
        -label          => 'Filter',
        -command        => $filter,
        -accelerator    => 'Return',
        );
    $search_menu->add('command',
        -label          => 'Back',
        -command        => $back,
        -accelerator    => 'Esc',
        );
    my $reset = sub{ $self->reset_search };
    $search_menu->add('command',
       -label          => 'Reset',
       -command        => $reset,
       -accelerator    => 'Ctrl+R',
       );

    my $collapse_all = sub{ $self->collapse_all };
    $view_menu->add('command',
        -label          => 'Collapse all',
        -command        => $collapse_all,
        -accelerator    => 'Ctrl+Left',
        );
    my $expand_all = sub{ $self->expand_all };
    $view_menu->add('command',
        -label          => 'Expand all',
        -command        => $expand_all,
        -accelerator    => 'Ctrl+Right',
        );

    $top->bind('<Return>', $filter);
    $top->bind('<Escape>', $back);
    $top->bind('<Control-r>', $reset);
    $top->bind('<Control-R>', $reset);
    $top->bind('<Control-Left>', $collapse_all);
    $top->bind('<Control-Right>', $expand_all);
    $top->bind('<Destroy>', sub{ $self = undef });

    $self->calcualte_text_column_sizes;

    $self->fix_window_min_max_sizes;
    return;
}

sub redraw {
    my ($self) = @_;

    $self->update_snail_trail;
    $self->do_render;
}

sub do_filter {
    my ($self) = @_;
    
    my $new_cllctn = $self->SearchHistory->search($self->{'_entry_search_string'})
        or return;
    $self->set_search_entry($new_cllctn->search_string);
    $self->redraw;
}

sub go_back {
    my ($self) = @_;

    # Save any typing done in the search Entry
    $self->current_Collection->search_string($self->{'_entry_search_string'});

    my $sh = $self->SearchHistory;
    my $cllctn = $sh->back or return;
    $self->set_search_entry($cllctn->search_string);
    $self->redraw;
}

sub reset_search {
    my ($self) = @_;

    my $sh = $self->SearchHistory;
    $sh->reset_search;
    $self->set_search_entry('');
    my $steps = $self->snail_trail_steps;
    foreach my $s (@$steps) {
        $s->packForget;
    }
    $self->redraw;
}

sub collapse_all {
    my ($self) = @_;

    $self->current_Collection->collapse_all;
    $self->redraw;
}

sub expand_all {
    my ($self) = @_;

    $self->current_Collection->expand_all;
    $self->redraw;
}

sub set_search_entry {
    my ($self, $string) = @_;

    $self->{'_entry_search_string'} = $string;
    $self->{'_search_Entry'}->icursor('end');    
}

sub update_snail_trail {
    my ($self) = @_;

    my ($I, @trail) = $self->SearchHistory->index_and_search_string_list;
    my $trail_steps = $self->snail_trail_steps;
    for (my $i = 0; $i < @trail; $i++) {
        my $step = $trail_steps->[$i] ||= $self->{'_snail_trail_frame'}->Label(
            -relief => 'groove',
            -padx   => 10,
            -pady   => 2,
            -borderwidth => 2,
            );
        $step->pack(-side => 'left', -padx => 2);
        $step->configure(
            -text => $trail[$i],
            -font   => ['Helvetica', 12, $i == $I ? 'bold' : 'normal'],
            );
    }
}

sub snail_trail_steps {
    my ($self) = @_;

    return $self->{'_snail_trail_steps'} ||= [];
}

sub SearchHistory {
    my ($self, $hist) = @_;
    
    if ($hist) {
        $self->{'_SearchHistory'} = $hist;
    }
    return $self->{'_SearchHistory'};
}

sub current_Collection {
    my ($self) = @_;

    return $self->SearchHistory->current_Collection;
}

sub current_Bracket {
    my ($self, $bkt) = @_;
    
    if ($bkt) {
        $self->{'_current_Bracket'} = $bkt;
    }
    return $self->{'_current_Bracket'};
}

sub name_max_x {
    my ($self, $bkt, $max_x) = @_;

    if ($bkt and $max_x) {
        $self->{'_name_max_x'}{$bkt} = $max_x;
    }
    else {
        return $self->{'_name_max_x'}{$self->current_Bracket};
    }
}

sub do_render {
    my ($self) = @_;

    $self->canvas->delete('all');

    my $cllctn = $self->current_Collection;
    $cllctn->update_all_Bracket_selection;
    my @items = $cllctn->list_visible_Items;
    for (my $i = 0; $i < @items; $i++) {
        $self->draw_Item($i, $items[$i]);
    }

    $self->set_scroll_region_and_maxsize;
    return;
}

sub draw_Item {
    my ($self, $row, $item) = @_;

    my $canvas = $self->canvas;
    my $row_height = $self->row_height;
    my $pad = int $self->font_size * 0.4;
    my $x = $row_height * $item->indent;
    my $y = $row * ($row_height + $pad);

    # Brackets have an arrow to expand or contract thier contents
    if ($item->is_Bracket) {
        $self->draw_arrow($item, $x, $y);
        $self->current_Bracket($item);
    }

    # Both Brackets and Columns have a checkbutton and their name drawn
    $x += $row_height;
    $self->draw_checkbutton($item, $x, $y);
    $x += $row_height;

    my $txt_id = $canvas->createText(
        $x, $y,
        -anchor => 'nw',
        -text   => $item->name,
        -font   => $self->normal_font,
        );
    $canvas->bind($txt_id, '<Button-1>', sub {
        $item->selected(! $item->selected);
        $self->update_item_select_state($item);
        });

    # Draw status indicator and description for Columns
    unless ($item->is_Bracket) {
        $x += $row_height + $self->name_max_x;
        $self->draw_status_indicator($item, $x, $y);
        $x += $row_height + $self->{'_status_max_x'};
        $canvas->createText(
            $x, $y,
            -anchor => 'nw',
            -text   => $item->Filter->description,
            -font   => $self->normal_font,
            );        
    }
}

sub normal_font {
    my ($self) = @_;

    return ['Helvetica', $self->font_size, 'normal'],
}

sub draw_status_indicator {
    my ($self, $item, $x, $y) = @_;

    my $canvas = $self->canvas;
    my ($dark, $light) = $item->status_colors;
    my $width = $self->{'_status_max_x'};
    $canvas->createRectangle(
        $x - 1, $y - 1, $x + $width + 1, $y + $self->{'_max_y'} + 1,
        -fill       => $light,
        -outline    => $dark,
        -tags       => ["STATUS_RECTANGLE $item"],
        );

    $canvas->createText(
        $x + ($width / 2), $y,
        -anchor => 'n',
        -text   => $item->status,
        -font   => $self->normal_font,
        -tags       => ["STATUS_LABEL $item"],
        );

    # For looking at appearance of status indicators
    my $next = sub { $self->next_status($item) };
    $canvas->bind("STATUS_RECTANGLE $item", '<Button-1>', $next);
    $canvas->bind("STATUS_LABEL $item",     '<Button-1>', $next);
}

sub next_status {
    my ($self, $item) = @_;

    my @status = Bio::Otter::Lace::Source::Item::Column::VALID_STATUS_LIST();
    my $this = $item->status;
    for (my $i = 0; $i < @status; $i++) {
        if ($status[$i] eq $this) {
            my $j = $i + 1;
            if ($j == @status) {
                $j = 0;
            }
            $item->status($status[$j]);
            $self->update_status_indicator($item);
        }
    }
}

sub update_status_indicator {
    my ($self, $item) = @_;

    my $canvas = $self->canvas;
    my ($dark, $light) = $item->status_colors;
    $canvas->itemconfigure("STATUS_RECTANGLE $item",
        -fill       => $light,
        -outline    => $dark,
        );
    $canvas->itemconfigure("STATUS_LABEL $item",
        -text   => $item->status,
        );
}

{
    my $on_checkbutton_xpm;
    my $off_checkbutton_xpm;

    sub draw_checkbutton {
        my ($self, $item, $x, $y) = @_;

        my $canvas = $self->canvas;
        my $is_selected = $item->selected;
        my $img;
        if ($is_selected) {
            $img = $on_checkbutton_xpm ||= Tk::Utils::CanvasXPMs::on_checkbutton_xpm($canvas);
        }
        else {
            $img = $off_checkbutton_xpm ||= Tk::Utils::CanvasXPMs::off_checkbutton_xpm($canvas);
        }
        my $img_id = $canvas->createImage(
            $x, $y,
            -anchor => 'nw',
            -image  => $img,
            );
        $canvas->bind($img_id, '<Button-1>', sub {
            $item->selected(! $is_selected);
            $self->update_item_select_state($item);
            });
    }
}

sub update_item_select_state {
    my ($self, $item) = @_;

    my $cllctn = $self->current_Collection;
    if ($item->is_Bracket) {
        $cllctn->select_Bracket($item);
    }
    $self->do_render;
}

{
    my $arrow_right_xpm;
    my $arrow_right_active_xpm;

    my $arrow_down_xpm;
    my $arrow_down_active_xpm;

    sub draw_arrow {
        my ($self, $item, $x, $y) = @_;

        my $canvas = $self->canvas;
        my $is_collapsed = $self->current_Collection->is_collapsed($item);
        my ($img, $active_img);
        if ($is_collapsed) {
            $img        = $arrow_right_xpm        ||= Tk::Utils::CanvasXPMs::arrow_right_xpm($canvas);
            $active_img = $arrow_right_active_xpm ||= Tk::Utils::CanvasXPMs::arrow_right_active_xpm($canvas);            
        }
        else {
            $img        = $arrow_down_xpm        ||= Tk::Utils::CanvasXPMs::arrow_down_xpm($canvas);
            $active_img = $arrow_down_active_xpm ||= Tk::Utils::CanvasXPMs::arrow_down_active_xpm($canvas);
        }
        my $img_id = $canvas->createImage(
            $x, $y,
            -anchor => 'nw',
            -image  => $img,
            -activeimage => $active_img,
            );
        $canvas->bind($img_id, '<Button-1>', sub {
            $self->current_Collection->is_collapsed($item, ! $is_collapsed);
            $self->do_render;
            });
    }
    
}

sub calcualte_text_column_sizes {
    my ($self) = @_;

    my $font = $self->normal_font;
    my $cllctn = $self->current_Collection;

    my @status = Bio::Otter::Lace::Source::Item::Column::VALID_STATUS_LIST();
    my ($status_max_x, $max_y) = $self->max_x_y_of_text_array($font, @status);
    $self->{'_status_max_x'} = 4 + $status_max_x;
    $self->{'_max_y'} = $max_y;

    foreach my $bkt ($cllctn->list_Brackets) {
        my $next_level = $bkt->indent + 1;
        my @names = map { $_->name }
            grep { $_->indent == $next_level } $cllctn->get_Bracket_contents($bkt);
        my ($name_max_x) = $self->max_x_y_of_text_array($font, @names);
        $self->name_max_x($bkt, $name_max_x);
    }
}

1;

__END__

=head1 NAME - CanvasWindow::ColumnChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

