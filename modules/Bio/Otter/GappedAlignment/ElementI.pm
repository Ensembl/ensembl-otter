
### Bio::Otter::GappedAlignment::ElementI

package Bio::Otter::GappedAlignment::ElementI;

use strict;
use warnings;

use Carp;
use List::Util qw(max);
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

sub divide {
    my ($self, $split_len) = @_;

    my $q_rem = $self->query_length  - $split_len;
    my $t_rem = $self->target_length - $split_len;

    if ($t_rem <= 0 and $q_rem <= 0) {
        croak sprintf("Cannot split %s by %d", $self->string, $split_len);
    }

    $q_rem = 0 if $q_rem < 0;
    $t_rem = 0 if $t_rem < 0;

    my $q_split = $self->query_length  - $q_rem;
    my $t_split = $self->target_length - $t_rem;

    my $first     = $self->new($q_split, $t_split);
    my $remainder = $self->new($q_rem,   $t_rem);

    return ($first, $remainder);
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

sub cigar_type {
    my $self = shift;
    # Pure virtual
    my $type = ucfirst $self->long_type;
    croak "cigar_type must be provided by child class '$type'";
}

sub cigar_length {
    my $self = shift;
    return max($self->query_length, $self->target_length);
}

sub ensembl_cigar_string {
    my $self = shift;
    my $len  = $self->cigar_length;
    my $type = $self->cigar_type;
    return $len > 1 ? $len . $type : $type;
}

sub is_intronic {
    my $self = shift;
    return $self->type =~ /^[35I]$/;
}

1;

__END__

=head1 NAME - Bio::Otter::GappedAlignment::ElementI

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
