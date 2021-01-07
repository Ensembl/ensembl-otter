=head1 LICENSE

Copyright [2018-2021] EMBL-European Bioinformatics Institute

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


### Bio::Otter::Fetch::GFF

package Bio::Otter::Fetch::GFF;

use strict;
use warnings;

use Carp;

use Fcntl qw(:seek); # get the SEEK_* constants

use Bio::Otter::Fetch::GFF::Feature;

# constructor

sub new {
    my ($pkg, %arg_hash) = @_;
    my $new = bless { }, $pkg;
    $new->_init(\%arg_hash);
    return $new;
}

sub _init {
    my ($self, $arg_hash) = @_;

    my ($file) = @{$arg_hash}{qw( -file )};

    open my $handle, '<', $file
        or die sprintf "failed to open GFF file '%s': $!", $file;
    $self->{'handle'} = $handle;

    my $feature_tell = tell $handle;
    while (<$handle>) {
        last unless /^#/;
        $feature_tell = tell $handle;
    }
    $self->{'feature_tell'} = $feature_tell;

    return;
}

# features

sub features {
    my ($self, $chr, $start, $end) = @_;

    my $seq_id = $chr;
    my $features = [ ];

    my $handle = $self->handle;
    my $feature_tell = $self->feature_tell;
    seek $handle, $feature_tell, SEEK_SET;

    while (<$handle>) {
        chomp;
        next if /^#/;
        my $feature = Bio::Otter::Fetch::GFF::Feature->new($_);
        (
         $feature->seq_id eq $seq_id &&
         $feature->start  >= $start  &&
         $feature->end    <= $end    &&
         1 ) or next;
        push @{$features}, $feature;
    }

    return $features;
}

# destructor

sub DESTROY {
    my ($self) = @_;
    my $handle = $self->{'handle'};
    close $handle if $handle;
    return;
}

# attributes

sub handle {
    my ($self) = @_;
    my $handle = $self->{'handle'};
    return $handle;
}

sub feature_tell {
    my ($self) = @_;
    my $feature_tell = $self->{'feature_tell'};
    return $feature_tell;
}

1;

__END__

=head1 NAME - Bio::Otter::Fetch::GFF

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

