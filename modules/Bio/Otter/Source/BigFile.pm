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


### Bio::Otter::Source::BigFile

package Bio::Otter::Source::BigFile;

use strict;
use warnings;

use Carp;
use URI::Escape qw( uri_escape );

use base 'Bio::Otter::Source';

my @keys = qw( description file csver );

sub new {
    my ($pkg, $name, $config) = @_;

    for (@keys) {
        confess "missing BigFile configuration parameter: $_"
            unless defined $config->{$_};
    }

    my $self = { name => $name, %{$config} };
    bless $self, $pkg;

    if (my $class = delete $self->{classification}) {
        $self->classification($class);
    }

    return $self;
}

# source methods

sub featuresets {
    my ($self) = @_;
    return [ $self->name ];
}

sub _url_query_string { ## no critic(Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($self, $session) = @_;
    return _query_string($self->url_query($session));
}

sub content_type { return; }
sub zmap_style  { confess  "zmap_style() not implemented in ", ref(shift); }
sub script_name { confess "script_name() not implemented in ", ref(shift); }

# GFF methods

my $bigfile_parameters = [
    qw(
        file
        gff_source
        ),
    [ qw( csver csver_remote ) ],
    ];

sub url_query {
    my ($self, $session) = @_;
    my $slice = $session->slice;
    my $DataSet = $session->DataSet;
    my $query = {
        chr   => $slice->ssname,
        start => $slice->start,
        end   => $slice->end,
        dataset => $DataSet->name,
        ( map { $self->_param_value($_) } @{$bigfile_parameters} ),
        gff_version => $DataSet->gff_version,
        %{$session->core_script_arguments},
    };
    return $query;
}

# Resource bins

sub init_resource_bin {
    my ($self) = @_;

    my $resource_bin = $self->resource_bin;
    $resource_bin and return $resource_bin; # already explicitly set

    $resource_bin = $self->resource_bin_from_uri($self->file);

    # warn "setting '", $self->name, "' resource_bin to: '", $resource_bin, "'\n";
    return $self->resource_bin($resource_bin);
}

# NB: the following subroutines are *not* methods

sub _query_string {
    my ($query) = @_;
    my @arguments;
    for my $key (sort keys %{$query}) {
        my $value = $query->{$key};
        next unless defined $value;
        push @arguments, sprintf '--%s=%s', $key, uri_escape($value);
    }
    my $query_string = join '&', @arguments;
    return $query_string;
}

1;

__END__

=head1 NAME - Bio::Otter::Source::BigFile

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

