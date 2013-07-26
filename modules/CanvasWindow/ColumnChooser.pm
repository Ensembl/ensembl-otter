
### CanvasWindow::ColumnChooser

package CanvasWindow::ColumnChooser;

use strict;
use warnings;

use base 'CanvasWindow';

sub new {
    my ($pkg, $tk, @rest) = @_;

    my $top_frame = $tk->Frame->pack(
        -side => 'top',
        -fill => 'x',
        );

    my $self = $pkg->SUPER::new($tk, @rest);
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

    $self->font_size(12);

    $self->column_Collection($cllctn);

    my $top = $self->top_window;
    my $top_frame = $self->top_frame;

    my $render = sub{ $self->do_render };
    $top_frame->Button(-text => 'Filter', -command => $render)->pack(-side => 'right');
    my $entry = $top_frame->Entry(
        -width        => 60,
        -textvariable => \$self->{'_render_query_string'}
    )->pack(-side => 'right');

    $entry->bind('<Return>', $render);

    $top->bind('<Destroy>', sub{ $self = undef });
    $self->fix_window_min_max_sizes;

    return;
}

sub column_Collection {
    my ($self, $cllctn) = @_;
    
    if ($cllctn) {
        $self->{'_column_Collection'} = $cllctn;
    }
    return $self->{'_column_Collection'};
}

sub do_render {
    my ($self) = @_;

    my $cllctn = $self->column_Collection;
    my @items = $cllctn->list_Items;
    for (my $i = 0; $i < @items; $i++) {
        $self->draw_branch($i, $items[$i]);
    }

    $self->fix_window_min_max_sizes;
    return;
}

sub draw_branch {
    my ($self, $row, $column) = @_;
    
    my $canvas = $self->canvas;
    my $row_height = $self->row_height;
    my $pad = int $self->font_size * 0.4;
    my $y_start = $row * ($row_height + $pad);
    $canvas->createWindow(
        $row_height / 2, $y_start,
        -anchor => 'nw',
        -width  => $row_height - 4,
        -height => $row_height - 4,
        -window     => $canvas->Checkbutton(
            -indicatoron    => 0,
            # -width  => $self->font_size,
            # -height => $self->font_size,
            # -padx   => 2,
            # -pady   => 2,
            # -justify    => 'center',
            -variable       => \$column->{'_wanted'},
            # -activebackground => 'red',
            -activeforeground => 'red',
            # -background     => 'white',
            ),
        );
    $canvas->createText(
        2 * $row_height, $y_start,
        -anchor => 'nw',
        -text   => $column->name,
        -font   => ['Helvetica', $self->font_size, 'normal'],
        );
    $canvas->createText(
        20 * $row_height, $y_start,
        -anchor => 'nw',
        -text   => $column->description,
        -font   => ['Helvetica', $self->font_size, 'normal'],
        );
    # $canvas->createRectangle(
    #     0, $y_start, 60 * $self->font_size, $y_start + $row_height,
    #     -fill       => 'LightBlue',
    #     -outline    => undef,
    #     );
}

1;

__END__

=head1 NAME - CanvasWindow::ColumnChooser

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

