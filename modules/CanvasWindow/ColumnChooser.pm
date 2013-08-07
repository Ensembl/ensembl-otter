
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

    $self->make_menu('File');

    $self->font_size(12);

    my $hist = Bio::Otter::Lace::Source::SearchHistory->new($cllctn);
    $self->SearchHistory($hist);

    my $top = $self->top_window;
    my $top_frame = $self->top_frame;
    my $snail_frame  = $top_frame->Frame->pack(-side => 'top');
    my $search_frame = $top_frame->Frame->pack(-side => 'top');

    $self->{'_snail_trail_text'} = $hist->snail_trail_text;
    $snail_frame->Label(
        -textvariable => \$self->{'_snail_trail_text'},
        )->pack(-side => 'left');

    my $entry = $self->{'_search_Entry'} = $search_frame->Entry(
        -width        => 60,
        -textvariable => \$self->{'_entry_search_string'},
    )->pack(-side => 'left');
    $self->set_search_entry($cllctn->search_string);

    my $filter = sub{ $self->do_filter };
    $search_frame->Button(-text => 'Filter', -command => $filter)->pack(-side => 'left');

    my $back = sub{ $self->go_back };
    $search_frame->Button(-text => 'Back', -command => $back)->pack(-side => 'left');

    $entry->bind('<Return>', $filter);
    $entry->bind('<Escape>', $back);

    $top->bind('<Destroy>', sub{ $self = undef });
    $self->fix_window_min_max_sizes;

    return;
}

sub do_filter {
    my ($self) = @_;
    
    my $new_cllctn = $self->SearchHistory->search($self->{'_entry_search_string'})
        or return;
    $self->set_search_entry($new_cllctn->search_string);
    $self->update_snail_trail_label;
    $self->do_render;
}

sub go_back {
    my ($self) = @_;

    # Save any typing done in the search Entry
    $self->current_Collection->search_string($self->{'_entry_search_string'});

    my $sh = $self->SearchHistory;
    my $cllctn = $sh->back or return;
    $self->set_search_entry($cllctn->search_string);
    $self->update_snail_trail_label;
    $self->do_render;
}

sub set_search_entry {
    my ($self, $string) = @_;

    $self->{'_entry_search_string'} = $string;
    $self->{'_search_Entry'}->icursor('end');    
}

sub update_snail_trail_label {
    my ($self) = @_;

    $self->{'_snail_trail_text'} = $self->SearchHistory->snail_trail_text;
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
    my $y_start = $row * ($row_height + $pad);
    my $x_start = $row_height * $item->indent;
    if ($item->is_Bracket) {
        $self->draw_arrow($item, $x_start, $y_start);
    }
    $self->draw_checkbutton($item, $x_start + $row_height, $y_start);
    $canvas->createText(
        $x_start + (2 * $row_height), $y_start,
        -anchor => 'nw',
        -text   => $item->name,
        -font   => ['Helvetica', $self->font_size, 'normal'],
        );
    unless ($item->is_Bracket) {
        $canvas->createText(
            $x_start + (20 * $row_height), $y_start,
            -anchor => 'nw',
            -text   => $item->Filter->description,
            -font   => ['Helvetica', $self->font_size, 'normal'],
            );        
    }
    # $canvas->createRectangle(
    #     0, $y_start, 60 * $self->font_size, $y_start + $row_height,
    #     -fill       => 'LightBlue',
    #     -outline    => undef,
    #     );
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
            # $canvas->delete($img_id);
            $item->selected(! $is_selected);
            # $self->draw_checkbutton($item, $x, $y);
            $self->update_brackets($item);
            });
    }
}

sub update_brackets {
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


1;

__END__

=head1 NAME - CanvasWindow::ColumnChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

