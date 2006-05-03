### Bio::Otter::Lace::Locator

# For keeping search results and (maybe) "bookmarks"

package Bio::Otter::Lace::Locator;

use strict;

sub new {
    my( $pkg ) = shift @_;

    my $self = bless {}, $pkg;

    $self->qname(shift @_) if @_;
    $self->qtype(shift @_) if @_;
    $self->clone_name(shift @_) if @_;
    $self->assemblies(shift @_) if @_;
    
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

sub clone_name { # a string
    my( $self, $clone_name ) = @_;
    
    if ($clone_name) {
        $self->{_clone_name} = $clone_name;
    }
    return $self->{_clone_name} || 'NOT FOUND';
}

sub assemblies { # a list reference
    my( $self, $assemblies ) = @_;
    
    if ($assemblies) {
        $self->{_assemblies} = $assemblies;
    }
    return $self->{_assemblies} || [];
}

1;
__END__

=head1 NAME - Bio::Otter::Lace::Locator

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk

