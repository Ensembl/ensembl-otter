
### GenomeCanvas::Band::ContigCartoon

package GenomeCanvas::Band::ContigCartoon;

use strict;
use Carp;
use base 'GenomeCanvas::Band';

sub render {
    my ($self) = @_;

    my $rpp       = $self->residues_per_pixel;
    my $y1        = $self->y_offset;
    my @tags      = $self->tags;
    my $canvas    = $self->canvas;
    my $font_size = $self->font_size;
    my $ctg_name  = $self->title;

    my $styles = $self->styles;

    my $slice  = $self->virtual_contig;
    my $x1     = 0;
    my $x2     = $x1 + ($slice->length / $rpp);
    my $y2     = $y1 + $font_size;
    my $y_half = $y1 + (($y2 - $y1) / 2);

    my $line_width = $font_size / 5;

    $canvas->createLine(
        $x1, $y_half, $x2, $y_half,
        -tags     => [@tags],
        -width    => $line_width,
        -fill     => 'black',
        -arrow    => 'last',
        -arrowshape => [
            $font_size,
            $font_size * 1.5,
            $font_size,
            ],
    );

    my $pipe_head = 1;
    my $rep_feats =
      $self->Client->get_rfs_from_dataset_sliceargs_analysis($self->DataSet,
        $slice, 'RepeatMasker', $pipe_head,);

    my %seen;
    my $pattern = "%8s  %4s  %s\n";
    foreach my $feat (@$rep_feats) {
        my $cons = $feat->repeat_consensus;
        my $name = $cons->repeat_class . ':' . $cons->name;

        unless ($seen{$name}) {
            $seen{$name} = 1;

            #printf $pattern, $ctg_name, 'REP',  $name;
        }

        my $feat_info = $styles->{'feature'}{$ctg_name}{$name} or next;
        my $style     = $styles->{'style'}{ $feat_info->{'label'} };

        my $x1 = $feat->start / $rpp;
        my $x2 = $feat->end / $rpp;
        $canvas->createRectangle(
            $x1, $y1, $x2, $y2,
            -outline => undef,
            -fill    => $style->{fill},
            -tags    => [@tags],
        );
        $canvas->createLine(
            $x1, $y1, $x2, $y1,
            -width => $line_width,
            -fill  => $style->{outline},
            -tags    => [@tags],
        );
        $canvas->createLine(
            $x1, $y2, $x2, $y2,
            -width => $line_width,
            -fill  => $style->{outline},
            -tags    => [@tags],
        );
    }

    my $min_gene_width = 10;    ### Could depend on font size

    # Draw long genes first so that the short genes get drawn on top.
    foreach
      my $gene (sort { $b->length <=> $a->length } @{ $slice->get_all_Genes })
    {
        next if $gene->type eq 'obsolete';
        my $name = $gene->gene_info->name->name;
        if ($name =~ /:/) {
            warn "Skipping '$name' gene\n";
            next;
        }
        my $desc = $gene->description || 'NO DESCRIPTION';

        my $feat_info = $styles->{'feature'}{$ctg_name}{$name} or next;
        my $style     = $styles->{'style'}{ $feat_info->{'label'} };

        printf STDERR $pattern, $ctg_name, 'GENE', qq{$name "$desc"};
        unless ($style) {
            next;
        }

        my $x1 = $gene->start / $rpp;
        my $x2 = $gene->end / $rpp;

        if ($x1 > $x2) {
            ($x1, $x2) = ($x2, $x1);
        }

        if (($x2 - $x1) < $min_gene_width) {
            my $centre = $x1 + (($x2 - $x1) / 2);
            $x1 = $centre - ($min_gene_width / 2);
            $x2 = $centre + ($min_gene_width / 2);
        }

        my @dash = ();
        if ($gene->type =~ /pseudo/i) {
            #@dash = (-dash   => [$line_width, 2 * $line_width]);
            @dash = (-dash   => '.');
        }
        $canvas->createOval(
            $x1, $y1, $x2, $y2,
            -width   => $line_width,
            -outline => $style->{outline},

            # Stippled if pseudogene
            @dash,
            -fill => $style->{fill},
            -tags => [@tags],
        );
    }

    # Features added by hand
    foreach my $name (keys %{ $styles->{'feature'} }) {
        my $feat_info = $styles->{'feature'}{$ctg_name}{$name};
        next unless $feat_info->{feature_start};

        my $style = $styles->{'style'}{ $feat_info->{'label'} }
          or die "No style info for feature '$name'";

        my $x1 = $feat_info->{feature_start} / $rpp;
        my $x2 = $feat_info->{feature_end} / $rpp;

        if ($x1 > $x2) {
            ($x1, $x2) = ($x2, $x1);
        }

        if (($x2 - $x1) < $min_gene_width) {
            my $centre = $x1 + (($x2 - $x1) / 2);
            $x1 = $centre - ($min_gene_width / 2);
            $x2 = $centre + ($min_gene_width / 2);
        }

        $canvas->createOval(
            $x1, $y1, $x2, $y2,
            -width   => $line_width,
            -outline => $style->{outline},

            # Always stippled
            -dash   => [$line_width, $line_width],
            -fill => $style->{fill},
            -tags => [@tags],
        );
    }
}

sub Client {
    my ($self, $Client) = @_;

    if ($Client) {
        $self->{'_Client'} = $Client;
    }
    return $self->{'_Client'};
}

sub DataSet {
    my ($self, $DataSet) = @_;

    if ($DataSet) {
        $self->{'_DataSet'} = $DataSet;
    }
    return $self->{'_DataSet'};
}

sub styles {
    my ($self, $styles) = @_;

    if ($styles) {
        $self->{'_styles'} = $styles;
    }
    return $self->{'_styles'};
}

sub read_config_file {
    my ($pkg, $conf_file) = @_;

    local $/ = "";    # Split file on paragraphs

    open my $conf, $conf_file
      or confess "Can't read '$conf_file' : $!";

    my $styles = {};

    my $out_fill = get_colours();

    my $i = 0;
    while (<$conf>) {
        my ($label) = /^Label\s+(.+)/im
          or next;
        my ($outline, $fill) = @{$out_fill->[$i]};
        $i++;
        #my ($outline)  = /^Outline\s+(.+)/im;
        #my ($fill)     = /^Fill\s+(.+)/im;
        my $gene_style = {
            fill            => $fill,
            outline         => $outline,
            file_position   => $i,
        };
        $styles->{'style'}{$label} = $gene_style;

        while (/(Ctg \d+)\s+(GENE|REP)\s+(.*)/mg) {
            my $ctg_name            = $1;
            $gene_style->{'type'}   = $2;
            my $rest                = $3;
            my $feat_info = { label => $label, };
            my $feature_name;
            if ($rest =~ /start=(\d+)\s+end=(\d+)\s*(.*)/) {
                $feat_info->{'feature_start'} = $1;
                $feat_info->{'feature_end'}   = $2;
                $feat_info->{'description'}   = $3;
                $feature_name                 = "$1-$2";
            }
            elsif ($rest =~ /(\S+)(?:\s+"?([^"]+))?/) {
                $feature_name = $1;
                $feat_info->{'description'} = $2;
            }
            else {
                confess "Unexpected line end format: '$rest' in paragraph:\n$_";
            }
            $feat_info->{'description'} =~ s/\s+$//
              if defined $feat_info->{'description'};

            $styles->{'feature'}{$ctg_name}{$feature_name} = $feat_info;
        }
    }
    close $conf or confess "Error reading '$conf_file' : $!";

    return $styles;
}


sub get_colours {

    my @palette = qw{
        black
        OrangeRed
        CornflowerBlue
        YellowGreen
        gold
        SaddleBrown
        violet
        };

    my $outline_fill = [];
    for (my $i = 0; $i < @palette; $i++) {
        my $outline = $palette[$i];
        for (my $j = 0; $j < @palette; $j++) {
            next if $i == $j;   # Fill must be different from outline
            my $fill = $palette[$j];
            push @$outline_fill, [$outline, $fill];
        }
    }

    return $outline_fill;
}


1;

__END__

=head1 NAME - GenomeCanvas::Band::ContigCartoon

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

