
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


sub chromosomes_per_row {
    my( $self, $chromosomes_per_row ) = @_;
    
    if ($chromosomes_per_row) {
        $self->{'_chromosomes_per_row'} = $chromosomes_per_row;
    }
    return $self->{'_chromosomes_per_row'} || 12;
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
    
    my $max = $self->chromosomes_per_row;
    my $set = [];
    my @all_set = ($set);
    foreach my $chr ($self->get_all_Chromosomes) {
        push(@$set, $chr);
        if (@$set >= $max) {
            $set = [];
            push(@all_set, $set);
        }
    }
    
    my $pad = $self->pad;
    my ($x, $y) = ($pad, $pad);
    foreach my $set (@all_set) {
        $y = $self->draw_chromsome_set($x, $y, $set);
        $y += $pad * 2;
    }
}

sub draw_chromsome_set {
    my( $self, $x, $y, $set ) = @_;

    warn sprintf "Drawing set of %d chromsomes\n", scalar @$set;

    my $scale = $self->Mb_per_pixel;
    my $canvas = $self->canvas;
    my $pad = $self->pad;
    my $max_chr_height = 0;
    foreach my $chr (@$set) {
        $chr->Mb_per_pixel($scale);
        my $h = $chr->height;
        warn "height = $h";
        $max_chr_height = $h if $h > $max_chr_height;
    }
    
    foreach my $chr (@$set) {
        $chr->set_initial_and_terminal_bands;
        $chr->draw($self, $x, $y + $max_chr_height - $chr->height);
        $x += $chr->width + $pad;
    }
    return $max_chr_height + $self->pad + $self->font_size;
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

