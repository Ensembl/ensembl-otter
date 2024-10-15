=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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


### Bio::Otter::Lace::PipelineStatus

package Bio::Otter::Lace::PipelineStatus;

use strict;
use warnings;
use Carp;

my $ana_root = 'SubmitContig';

sub new {
    my ($pkg) = @_;
    my $self = {
        'completed_count' => 0,
        '_entries' => {},
    };
    bless $self, $pkg;
    return $self;
}

sub entry {
    my ($self, $key, $value) = @_;

    if($value) {
        $self->{_entries}{$key} = $value;
    }
    return $self->{_entries}{$key};
}

sub add_analysis {
    my ($self, $ana_name, $values) = @_;

    if(@$values) {
        my ($created, $version) = @$values;
        $self->entry($ana_name, { 'created' => $created, 'version' => $version });
        $self->{completed_count}++;
    } else {
        $self->entry($ana_name, {});
    }

    return;
}

sub all_analyses {
    my ($self) = @_;
    my @analyses =
        sort { ($a eq $ana_root) ? -1 : ($b eq $ana_root) ? 1 : ($a cmp $b); } keys %{$self->{_entries}};
    return @analyses;
}

# Returns an array used by CanvasWindow::SequenceNotes::Status
# to display status information.
sub display_list {
    my ($self) = @_;

    my @display_list = ();
    foreach my $ana_name ($self->all_analyses()) {
        my $entry = $self->entry($ana_name);
        push @display_list, {
                'name'   => $ana_name,
                (keys %$entry)
                    ? ( 'status' => 'completed', %$entry )
                    : ( 'status' => 'missing', 'created' => '-', 'version' => '-',),
        };
    }
    return \@display_list;
}

# Called by CanvasWindow::SequenceNotes for displaying overall status of clone
sub short_display {
    my ($self) = @_;

    my $total_entries = scalar(keys %{$self->{_entries}});

    return (!$total_entries)
            ? 'unavailable'
            : ($self->{'completed_count'} == $total_entries)
                ? 'completed'
                : 'missing';

}

1;

__END__

=head1 NAME - Bio::Otter::Lace::PipelineStatus

=head1 SYNOPSIS

=head1 DESCRIPTION

Designed to have hold information on the status of a 
CloneSequence in the pipeline.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

