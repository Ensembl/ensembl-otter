
### Bio::Otter::GappedAlignment::ElementI

package Bio::Otter::GappedAlignment::ElementI;

use strict;
use warnings;

use Readonly;

use Bio::Otter::GappedAlignment::ElementTypes;

sub new {
    my ($class, $query_length, $target_length) = @_;

    my $pkg = ref($class) || $class;
    my $self = bless {}, $pkg;

    $self->query_length($query_length);
    $self->target_length($target_length);

    $self->validate;

    return $self;
}

sub make_copy {
    my $self = shift;
    return $self->new($self->query_length, $self->target_length);
}

sub query_length {
    my ($self, $query_length) = @_;
    if (defined $query_length) {
        $self->{'_query_length'} = $query_length;
    }
    return $self->{'_query_length'};
}

sub target_length {
    my ($self, $target_length) = @_;
    if (defined $target_length) {
        $self->{'_target_length'} = $target_length;
    }
    return $self->{'_target_length'};
}

sub validate {
    return 1;
}

sub string {
    my $self = shift;
    return sprintf('%s %d %d', $self->type, $self->query_length, $self->target_length);
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::ElementI

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
