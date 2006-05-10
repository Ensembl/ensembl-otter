### Bio::Otter::Lace::Access

package Bio::Otter::Lace::Access;

use strict;
use Carp;

sub new {
    my $pkg = shift;
    return bless {}, $pkg;
}

sub author {
    my( $self, $author ) = @_;
    if (defined $author) {
        $self->{'_author'} = $author;
    }
    return $self->{'_author'};
}

sub sequenceset_name {
    my( $self, $sequenceset_name ) = @_;
    if (defined $sequenceset_name) {
        $self->{'_sequenceset_name'} = $sequenceset_name;
    }
    return $self->{'_sequenceset_name'};
}

sub access_type {
    my( $self, $access_type ) = @_;
    if (defined $access_type) {
        $self->{'_access_type'} = $access_type;
    }
    return $self->{'_access_type'};
}

1;


__END__

=head1 NAME - Bio::Otter::Lace::Access

=head1 DESCRIPTION

Defines the access status of each sequence set with resp. to author
Known access types are RW, R

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk

