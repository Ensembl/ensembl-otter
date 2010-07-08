### Bio::Otter::Lace::Locator

# For keeping search results and (maybe) "bookmarks"

package Bio::Otter::Lace::Locator;

use strict;
use warnings;

sub new {
    my( $pkg, $qname, $qtype, $component_names, $assembly ) = @_;

    my $self = bless {}, $pkg;

    $self->qname($qname) if $qname;
    $self->qtype($qtype) if $qtype;
    $self->component_names($component_names) if $component_names;
    $self->assembly($assembly) if $assembly;
    
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

sub component_names { # a list reference
    my( $self, $component_names ) = @_;
    
    if ($component_names) {
        $self->{_component_names} = $component_names;
    }
    return $self->{_component_names} || [];
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

