
### Bio::Otter::Lace::SequenceNote

package Bio::Otter::Lace::SequenceNote;

use strict;
use warnings;

sub new {
    my ($pkg) = @_;
    
    return bless {}, $pkg;
}

sub text {
    my ($self, $text) = @_;
    
    if ($text) {
        $self->{'_text'} = $text;
    }
    return $self->{'_text'};
}

sub timestamp {
    my ($self, $timestamp) = @_;
    
    if (defined $timestamp) {
        $self->{'_timestamp'} = $timestamp;
    }
    return $self->{'_timestamp'};
}

sub is_current {
    my ($self, $is_current) = @_;
    
    if (defined $is_current) {
        $self->{'_is_current'} = $is_current;
    }
    return $self->{'_is_current'};
}

sub author {
    my ($self, $author) = @_;
    
    if ($author) {
        $self->{'_author'} = $author;
    }
    return $self->{'_author'};
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::SequenceNote

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

