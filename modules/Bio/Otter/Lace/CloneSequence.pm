
### Bio::Otter::Lace::CloneSequence

package Bio::Otter::Lace::CloneSequence;

use strict;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub accession {
    my( $self, $accession ) = @_;
    
    if ($accession) {
        $self->{'_accession'} = $accession;
    }
    return $self->{'_accession'};
}

sub sv {
    my( $self, $sv ) = @_;
    
    if (defined $sv) {
        $self->{'_sv'} = $sv;
    }
    return $self->{'_sv'};
}

sub length {
    my( $self, $length ) = @_;
    
    if ($length) {
        $self->{'_length'} = $length;
    }
    return $self->{'_length'};
}

sub chromosome {
    my( $self, $chromosome ) = @_;
    
    if ($chromosome) {
        $self->{'_chromosome'} = $chromosome;
    }
    return $self->{'_chromosome'};
}

sub chr_start {
    my( $self, $chr_start ) = @_;
    
    if (defined $chr_start) {
        $self->{'_chr_start'} = $chr_start;
    }
    return $self->{'_chr_start'};
}

sub chr_end {
    my( $self, $chr_end ) = @_;
    
    if (defined $chr_end) {
        $self->{'_chr_end'} = $chr_end;
    }
    return $self->{'_chr_end'};
}

sub contig_start {
    my( $self, $contig_start ) = @_;
    
    if (defined $contig_start) {
        $self->{'_contig_start'} = $contig_start;
    }
    return $self->{'_contig_start'};
}

sub contig_end {
    my( $self, $contig_end ) = @_;
    
    if (defined $contig_end) {
        $self->{'_contig_end'} = $contig_end;
    }
    return $self->{'_contig_end'};
}

sub contig_strand {
    my( $self, $contig_strand ) = @_;
    
    if ($contig_strand) {
        $self->{'_contig_strand'} = $contig_strand;
    }
    return $self->{'_contig_strand'};
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::CloneSequence

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

