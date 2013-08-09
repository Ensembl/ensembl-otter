
### Bio::Otter::Lace::Source::Item::Column

package Bio::Otter::Lace::Source::Item::Column;

use strict;
use warnings;
use Carp;
use base 'Bio::Otter::Lace::Source::Item';

my @valid_status = qw{
    Loading Visible Hidden Empty Error
};
my %valid_status = map {$_ => 1} @valid_status;

sub VALID_STATUS_LIST {
    return @valid_status;
}

sub is_Bracket {
    return 0;
}

sub status {
    my ($self, $status) = @_;

    if ($status) {
        unless ($valid_status{$status}) {
            confess "Invalid status '$status'\n",
                "Should be one of: ", join(', ', keys %valid_status);
        }
        $self->{'_status'} = $status;
    }
    return $self->{'_status'} || $self->selected ? 'Selected' : 'Unwanted';
}

# For storing further info such as error messages, shown on mouse-over
sub status_detail {
    my ($self, $status_detail) = @_;

    if ($status_detail) {
        $self->{'_status_detail'} = $status_detail;
    }
    return $self->{'_status_detail'};
}

sub string {
    my ($self) = @_;

    return join("\n", $self->Filter->name, $self->Filter->description);
}

sub Filter {
    my ($self, $Filter) = @_;
    
    if ($Filter) {
        $self->{'_Filter'} = $Filter;
    }
    return $self->{'_Filter'};
}


1;

__END__

=head1 NAME - Bio::Otter::Lace::Source::Item::Column

=head1 DESCRIPTION

This object represents a leaf on the tree in the ColumnChooser window. It
contains a reference to a C<Bio::Otter::Filter> plus its current status
in the otter session.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

