
### Bio::Otter::Lace::Chromosome

package Bio::Otter::Lace::Chromosome;

use strict;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub chromosome_id {
    my( $self, $chromosome_id ) = @_;
    
    if ($chromosome_id) {
        $self->{'_chromosome_id'} = $chromosome_id;
    }
    return $self->{'_chromosome_id'};
}

sub name {
    my( $self, $name ) = @_;
    
    if ($name) {
        $self->{'_name'} = $name;
    }
    return $self->{'_name'};
}

sub length {
    my( $self, $length ) = @_;
    
    if (defined $length) {
        $self->{'_length'} = $length;
    }
    return $self->{'_length'};
}


1;

__END__

=head1 NAME - Bio::Otter::Lace::Chromosome

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

