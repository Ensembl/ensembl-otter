
### KaryotypeWindow

package KaryotypeWindow;

use strict;
use Carp;
use base 'CanvasWindow';
use KaryotypeWindow::Chromosome;

sub new {
    my $pkg = shift;

    my $self = $pkg->SUPER::new(@_);

    #$self->canvas->DefineBitmap(
    #    'gvar', 4, 1, pack('b4', '..11')
    #    );
    $self->canvas->DefineBitmap( 'gvar', 2, 2, pack( 'b2' x 2, '.1', '1.', ) );

    #$self->canvas->DefineBitmap(
    #    'gcen', 2, 1, pack('b2', '.1')
    #    );
    return $self;
}

sub get_all_Chromosomes {
    my ($self) = @_;

    if ( my $lst = $self->{'_Chromosome_list'} ) {
        return @$lst;
    }
    else {
        return;
    }
}

sub chromosomes_per_row {
    my ( $self, $chromosomes_per_row ) = @_;

    if ($chromosomes_per_row) {
        $self->{'_chromosomes_per_row'} = $chromosomes_per_row;
    }
    return $self->{'_chromosomes_per_row'} || 12;
}

sub add_Chromosome {
    my ( $self, $chr ) = @_;

    confess "Missing Chromosome argument" unless $chr;
    my $lst = $self->{'_Chromosome_list'} ||= [];
    push ( @$lst, $chr );
}

sub new_Chromosome {
    my ($self) = @_;

    my $chr = KaryotypeWindow::Chromosome->new;
    $self->add_Chromosome($chr);
    return $chr;
}

sub draw {
    my ($self) = @_;

    my $max     = $self->chromosomes_per_row;
    my $set     = [];
    my @all_set = ($set);
    foreach my $chr ( $self->get_all_Chromosomes ) {
        push ( @$set, $chr );
        if ( @$set >= $max ) {
            $set = [];
            push ( @all_set, $set );
        }
    }

    my $pad = $self->pad;
    my ( $x, $y ) = ( $pad, $pad );
    my $y_pos;
    foreach my $set (@all_set) {
        next unless @$set;
        $y = $self->draw_chromsome_set( $x, $y, $set );
        #$y += $pad;
        $y_pos += $y;
       
    }
    
    $self->_draw_scale( $x, $y_pos, scalar(@all_set), $max );

}

sub _draw_scale {
    my ( $self, $x, $y, $row_count, $max ) = @_;

    my $pad     = $self->pad;
    my $scale_y = $y - 75;
    my $scale_x = ( $pad * $max ) + $pad + 75;

    $self->{'_canvas'}->createText(
        $scale_x - 18, $scale_y, -text => 'Scale: ',
        -font => [ 'Helvetica', '10', 'bold' ],
    );

    $self->{'_canvas'}->createText(
        $scale_x + 17, $scale_y + 10, -text => '50 tRNAs',
        -font => [ 'Helvetica', '8' ],
    );

    $self->{'_canvas'}->createLine(
        $scale_x, $scale_y, $scale_x + 25, $scale_y, -fill => '#cc3333',
    );

    $self->{'_canvas'}->createLine(
        $scale_x, $scale_y - 2, $scale_x, $scale_y + 3, -fill => 'black',
    );

    $self->{'_canvas'}->createLine(
        $scale_x + 25, $scale_y - 2, $scale_x + 25, $scale_y + 3, -fill => 'black',
    );

}

sub draw_chromsome_set {
    my ( $self, $x, $y, $set ) = @_;

    warn sprintf "Drawing set of %d chromsomes\n", scalar @$set;

    my $scale          = $self->Mb_per_pixel;
    my $canvas         = $self->canvas;
    my $pad            = $self->pad;
    my $max_chr_height = 0;
    foreach my $chr (@$set) {
        $chr->Mb_per_pixel($scale);
        my $h = $chr->height;
        $max_chr_height = $h if $h > $max_chr_height;
    }

    foreach my $chr (@$set) {
        $chr->set_initial_and_terminal_bands;
        $chr->draw( $self, $x, $y + $max_chr_height - $chr->height );
        $x += $chr->width + $pad;

    }
    return $max_chr_height + $self->pad + $self->font_size + 50;
}

sub Mb_per_pixel {
    my ( $self, $Mb_per_pixel ) = @_;

    if ($Mb_per_pixel) {
        $self->{'_Mb_per_pixel'} = $Mb_per_pixel;
    }
    return $self->{'_Mb_per_pixel'} || 1;
}

sub pad {
    my ( $self, $pad ) = @_;

    if ($pad) {
        $self->{'_pad'} = $pad;
    }
    return $self->{'_pad'} || 70;
}

sub data {
    my ( $self, %data ) = @_;

    if (%data) {
        $self->{'_data'} = {%data};

    }

    return $self->{'_data'};

}
1;




__END__

=head1 NAME - KaryotypeWindow

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

