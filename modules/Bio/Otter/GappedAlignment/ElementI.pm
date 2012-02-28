
### Bio::Otter::GappedAlignment::ElementI

package Bio::Otter::GappedAlignment::ElementI;

use strict;
use warnings;

use Readonly;

use Bio::Otter::GappedAlignment::ElementTypes;

sub new {
    my ($pkg, $query_length, $target_length) = @_;

    my $self = bless {}, $pkg;

    $self->query_length($query_length);
    $self->target_length($target_length);

    $self->validate;

    return $self;
}

sub query_length {
    my ($self, $query_length) = @_;
    if ($query_length) {
        $self->{'_query_length'} = $query_length;
    }
    return $self->{'_query_length'};
}

sub target_length {
    my ($self, $target_length) = @_;
    if ($target_length) {
        $self->{'_target_length'} = $target_length;
    }
    return $self->{'_target_length'};
}

sub validate {
    return 1;
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::ElementI

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
