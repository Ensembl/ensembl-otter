
### GenomeCanvas::Band::ContigCartoon

package GenomeCanvas::Band::ContigCartoon;

use strict;
use Carp;
use base 'GenomeCanvas::Band';

sub render {
    my ($self) = @_;
    
    my $rpp         = $self->residues_per_pixel;
    my $y1          = $self->y_offset;
    my @tags        = $self->tags;
    my $canvas      = $self->canvas;
    my $font_size   = $self->font_size;
    my $ctg_name    = $self->title;
    
    my $styles = $self->read_config_file;
    
    my $slice = $self->virtual_contig;
    my $x1 = 0;
    my $x2 = $x1 + ($slice->length / $rpp);
    my $y2 = $y1 + (2 * $font_size);
    my $y_half = $y1 + (($y2 - $y1) / 2);
    
    $canvas->createLine(
        $x1,$y_half, $x2,$y_half,
        -tags       => [@tags],
        -width      => 2,
        -fill       => 'black',
        -capstyle   => 'round',
        );
    
    my $pipe_head = 1;
    my $rep_feats = $self->Client->get_rfs_from_dataset_sliceargs_analysis(
        $self->DataSet, $slice, 'RepeatMasker', $pipe_head,
        );
    
    my %seen;
    my $pattern = "%8s  %4s  %s\n";
    foreach my $feat (@$rep_feats) {
        my $cons = $feat->repeat_consensus;
        my $name = $cons->repeat_class . ':' . $cons->name;
        
        unless ($seen{$name}) {
            $seen{$name} = 1;
            printf $pattern, $ctg_name, 'REP',  $name;
        }
        
        next unless $styles->{$name};
        
        my $x1 = $feat->start / $rpp;
        my $x2 = $feat->end   / $rpp;
        $canvas->createRectangle(
            $x1,$y1, $x2,$y2,
            -outline    => undef,
            -fill       => 'Salmon',
            -tags       => [@tags],
            );
        $canvas->createLine(
            $x1,$y1, $x2,$y1,
            -width      => 2,
            -fill       => 'black',
            );
        $canvas->createLine(
            $x1,$y2, $x2,$y2,
            -width      => 2,
            -fill       => 'black',
            );
    }
    
    my $min_gene_width = 10;    ### Could depend on font size
    
    # Draw long genes first so that the short genes get drawn on top.
    foreach my $gene (sort {$b->length <=> $a->length} @{$slice->get_all_Genes}) {
        ### Truncate to slice
        next if $gene->type eq 'obsolete';
        my $name = $gene->gene_info->name->name;
        if ($name =~ /:/) {
            warn "Skipping '$name' gene\n";
            next;
        }
        my $desc = $gene->description || 'NO DESCRIPTION';
        printf $pattern, $ctg_name, 'GENE', qq{$name "$desc"};
        
        next unless $styles->{$name};
        
        my $x1 = $gene->start / $rpp;
        my $x2 = $gene->end   / $rpp;
        
        if ($x1 > $x2) {
            ($x1, $x2) = ($x2, $x1);
        }
        
        if (($x2 - $x1) < $min_gene_width) {
            my $centre = $x1 + (($x2 - $x1) / 2);
            $x1 = $centre - ($min_gene_width / 2);
            $x2 = $centre + ($min_gene_width / 2);
        }
        
        $canvas->createOval(
            $x1,$y1, $x2,$y2,
            -width      => 2,
            -outline    => 'black',
            -fill       => 'YellowGreen',
            #-fill       => undef,
            -tags       => [@tags],
            );
    }
}

sub Client {
    my( $self, $Client ) = @_;
    
    if ($Client) {
        $self->{'_Client'} = $Client;
    }
    return $self->{'_Client'};
}

sub DataSet {
    my( $self, $DataSet ) = @_;
    
    if ($DataSet) {
        $self->{'_DataSet'} = $DataSet;
    }
    return $self->{'_DataSet'};
}

sub config_file {
    my( $self, $config_file ) = @_;
    
    if ($config_file) {
        $self->{'_config_file'} = $config_file;
    }
    return $self->{'_config_file'};
}

sub read_config_file {
    my ($self) = @_;
    
    my $conf_file = $self->config_file;
    
    open my $conf, $conf_file
      or confess "Can't read '$conf_file' : $!";
    my $styles = {};
    while (<$conf>) {
        my ($type, $name, @rest) = split;
        $styles->{$name} = [@rest];
    }
    close $conf or confess "Error reading '$conf_file' : $!";
    
    return $styles;
}


1;

__END__

=head1 NAME - GenomeCanvas::Band::ContigCartoon

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

