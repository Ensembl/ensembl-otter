
### KaryotypeWindow

package KaryotypeWindow;

use strict;
use Carp;
use base 'CanvasWindow';
use KaryotypeWindow::Chromosome;

sub get_all_Chromosomes {
    my( $self ) = @_;
    
    if (my $lst = $self->{'_Chromosome_list'}) {
        return @$lst;
    } else {
        return;
    }
}

sub add_Chromosome {
    my( $self, $chr ) = @_;
    
    confess "Missing Chromosome argument" unless $chr;
    my $lst = $self->{'_Chromosome_list'} ||= [];
    push(@$lst, $chr);
}

sub new_Chromosome {
    my( $self ) = @_;
    
    my $chr = KaryotypeWindow::Chromosome->new;
    $self->add_Chromosome($chr);
    return $chr;
}

sub draw {
    my( $self ) = @_;
    
    my $scale = $self->Mb_per_pixel;
    my $pad = $self->pad;
    my $canvas = $self->canvas;
    my ($x, $y) = ($pad, $pad);
    foreach my $chr ($self->get_all_Chromosomes) {
        $chr->set_initial_and_terminal_bands;
        $chr->Mb_per_pixel($scale);
        $chr->draw($canvas, $x, $y);
        $x += $chr->width + $pad;
    }
}

sub Mb_per_pixel {
    my( $self, $Mb_per_pixel ) = @_;
    
    if ($Mb_per_pixel) {
        $self->{'_Mb_per_pixel'} = $Mb_per_pixel;
    }
    return $self->{'_Mb_per_pixel'} || 1;
}


sub pad {
    my( $self, $pad ) = @_;
    
    if ($pad) {
        $self->{'_pad'} = $pad;
    }
    return $self->{'_pad'} || 40;
}


1;

__END__

=head1 NAME - KaryotypeWindow

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

