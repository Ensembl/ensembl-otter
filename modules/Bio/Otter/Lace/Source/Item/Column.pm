
### Bio::Otter::Lace::Source::Item::Column

package Bio::Otter::Lace::Source::Item::Column;

use strict;
use warnings;
use Carp;
use Scalar::Util 'weaken';
use base 'Bio::Otter::Lace::Source::Item';

my (@valid_status, %status_color);

{
    no warnings "qw";
    my @_status_color_ini = qw{
        Available   #cccccc         #f0f0f0
        Selected    #ffe249         #fff4b6
        Loading     #ffbf49         #ffe5b6
        Visible     #a6dd33         #ccf37c
        Hidden      #d4f68d         #effed1
        Empty       #c0d4ee         #e2edfc
        Error       #ff907c         #ffbcb0
    };

    for (my $i = 0; $i < @_status_color_ini; $i += 3) {
        my ($status, $dark, $light) = @_status_color_ini[$i .. $i + 3];
        push(@valid_status, $status);
        $status_color{$status} = [$dark, $light];
    }
}

sub VALID_STATUS_LIST {
    return @valid_status;
}

sub new {
    my ($pkg) = @_;

    return bless {
        '_status'   => 'Available',
    }, $pkg;
}

sub is_Bracket {
    return 0;
}

sub is_stored {
    my($self, $flag) = @_;
    
    if (defined $flag) {
        $self->{'_is_stored'} = $flag ? 1 : 0;
    }
    return $self->{'_is_stored'};
}

sub confess_if_not_valid_status {
    my ($pkg_or_self, $status) = @_;

    unless ($status_color{$status}) {
        confess "Invalid status '$status'\n",
            "Should be one of: @valid_status";
    }
}

sub selected {
    my($self, $flag) = @_;
    
    if (defined $flag) {
        $self->{'_selected'} = $flag ? 1 : 0;
        my $status = $self->status;
        if ($self->{'_selected'}) {
            if ($status eq 'Available') {
                $self->status('Selected');
            }
            elsif ($status eq 'Error') {
                $self->status('Selected');
            }
            elsif ($status eq 'Hidden') {
                ### Need to do stuff
                $self->status('Visible');
            }
        }
        else {
            if ($status eq 'Selected') {
                $self->status('Available');
            }
            elsif ($status eq 'Visible') {
                $self->status('Hidden');
            }
        }
    }
    return $self->{'_selected'};
}

sub status {
    my ($self, $status) = @_;

    if ($status) {
        $self->confess_if_not_valid_status($status);
        my $old_status = $self->{'_status'};
        $self->{'_status'} = $status;
        if (my $call = $self->status_callback) {
            if ($status ne $old_status) {
                my ($obj, $method) = @$call;
                $obj->$method($self);
            }
        }
    }
    return $self->{'_status'};
}

sub status_colors {
    my ($self) = @_;

    return @{$status_color{$self->status}};
}

# For storing further info such as error messages, shown on mouse-over
sub status_detail {
    my ($self, $txt) = @_;

    if ($txt) {
        $self->{'_status_detail'} = $txt;
    }
    return $self->{'_status_detail'};
}

sub status_callback {
    my ($self, $sub) = @_;

    if ($sub) {
        weaken($sub->[0]);
        $self->{'_status_callback'} = $sub;
    }
    return $self->{'_status_callback'};
}

sub gff_file {
    my ($self, $gff_file) = @_;
    
    if ($gff_file) {
        $self->{'_gff_file'} = $gff_file;
    }
    return $self->{'_gff_file'};
}

sub process_gff {
    my($self, $flag) = @_;
    
    if (defined $flag) {
        $self->{'_process_gff'} = $flag ? 1 : 0;
    }
    return $self->{'_process_gff'};
}

sub string {
    my ($self) = @_;

    return join("\n", $self->name, $self->Filter->description, $self->status);
}

sub Filter {
    my ($self, $Filter) = @_;
    
    if ($Filter) {
        $self->{'_Filter'} = $Filter;
        $self->name($Filter->name);
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

