
### Bio::Otter::Lace::Source::Item::Column

package Bio::Otter::Lace::Source::Item::Column;

use strict;
use Carp;
use base 'Bio::Otter::Lace::Source::Item';

my @_status_color_ini = qw{
    Available   #cccccc         #f0f0f0
    Selected    #ffe249         #fff4b6
    Loading     #ffbf49         #ffe5b6
    Visible     #a6dd33         #ccf37c
    Hidden      #d4f68d         #effed1
    Empty       #c0d4ee         #e2edfc
    Error       #ff907c         #ffbcb0
};

my (@valid_status, %status_color);
for (my $i = 0; $i < @_status_color_ini; $i += 3) {
    my ($status, $dark, $light) = @_status_color_ini[$i .. $i + 3];
    push(@valid_status, $status);
    $status_color{$status} = [$dark, $light];
}

use warnings;

sub VALID_STATUS_LIST {
    return @valid_status;
}

sub is_Bracket {
    return 0;
}

sub status {
    my ($self, $status) = @_;

    if ($status) {
        unless ($status_color{$status}) {
            confess "Invalid status '$status'\n",
                "Should be one of: @valid_status";
        }
        $self->{'_status'} = $status;
    }
    return $self->{'_status'} || ($self->selected ? 'Selected' : 'Available');
}

sub status_colors {
    my ($self) = @_;

    return @{$status_color{$self->status}};
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

