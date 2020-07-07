=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut


### Bio::Otter::Lace::Chooser::Item::Column

package Bio::Otter::Lace::Chooser::Item::Column;

use strict;
use warnings;
use Carp;
use Scalar::Util 'weaken';
use base 'Bio::Otter::Lace::Chooser::Item';

my (@valid_status, %status_color);

{
    no warnings "qw";
    my @_status_color_ini = qw{
        Available   #cccccc         #f0f0f0
        Selected    #ffe249         #fff4b6
        Queued      #e8cba4         #fbebd5
        Loading     #ffbf49         #ffe5b6
        Processing  #ffbf49         #ffe5b6
        HitsQueued  #ffbf49         #ffe5b6
        HitsProcess #ffbf49         #ffe5b6
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

sub STATUS_COLORS_HASHREF {
    return \%status_color;
}

sub new {
    my ($pkg) = @_;

    my $new = {
        '_status'   => 'Available',
    };

    return bless $new, $pkg;
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
    my($self, $flag, $options) = @_;

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
            elsif ($options and $options->{force}) { # for user-requested reload
                $self->status('Selected');
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

    my $descr = $self->Filter->description;
    $descr = '' unless defined $descr;
    return join("\n", $self->name, $descr, $self->status);
}

sub Filter {
    my ($self, $Filter) = @_;

    if ($Filter) {
        $self->{'_Filter'} = $Filter;
        $self->name($Filter->name);
    }
    return $self->{'_Filter'};
}

sub internal_type {
    my ($self) = @_;

    my $filter = $self->Filter;
    return unless $filter;

    return $filter->internal;
}

sub internal_type_is {
    my ($self, $required) = @_;

    my $internal_type = $self->internal_type;
    return unless $internal_type;

    return ($internal_type eq $required);
}

sub internal_type_like {
    my ($self, $regexp) = @_;

    my $internal_type = $self->internal_type;
    return unless $internal_type;

    return ($internal_type =~ $regexp);
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::Chooser::Item::Column

=head1 DESCRIPTION

This object represents a leaf on the tree in the ColumnChooser
window. It contains a reference to a C<Bio::Otter::Source::Filter>
plus its current status in the otter session.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

