### Bio::Otter::Lace::Locator

# For keeping search results and (maybe) "bookmarks"

package Bio::Otter::Lace::Locator;

use strict;

sub new {
    my( $pkg ) = shift @_;

    my $self = bless {}, $pkg;

    $self->qname(shift @_) if @_;
    $self->qtype(shift @_) if @_;
    $self->clone_names(shift @_) if @_;
    $self->assembly(shift @_) if @_;
    
    return $self;
}

sub qname { # a string
    my( $self, $qname ) = @_;
    
    if ($qname) {
        $self->{_qname} = $qname;
    }
    return $self->{_qname};
}

sub qtype { # a string
    my( $self, $qtype ) = @_;
    
    if ($qtype) {
        $self->{_qtype} = $qtype;
    }
    return $self->{_qtype} || 'NOT FOUND';
}

sub clone_names { # a list reference
    my( $self, $clone_names ) = @_;
    
    if ($clone_names) {
        $self->{_clone_names} = $clone_names;
    }
    return $self->{_clone_names} || [];
}

sub assembly { # a string
    my( $self, $assembly ) = @_;
    
    if ($assembly) {
        $self->{_assembly} = $assembly;
    }
    return $self->{_assembly} || 'NOT FOUND';
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::Locator

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk

