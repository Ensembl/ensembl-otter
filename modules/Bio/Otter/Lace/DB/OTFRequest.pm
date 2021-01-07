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


### Bio::Otter::Lace::DB::OTFRequest

package Bio::Otter::Lace::DB::OTFRequest;

use strict;
use warnings;

sub new {
    my ($pkg, %args ) = @_;
    $args{'status'} //= 'new';
    my $self = bless { %args }, $pkg;
    return $self;
}

sub id {
    my ($self, @args) = @_;
    ($self->{'id'}) = @args if @args;
    my $id = $self->{'id'};
    return $id;
}

sub logic_name {
    my ($self, @args) = @_;
    ($self->{'logic_name'}) = @args if @args;
    my $logic_name = $self->{'logic_name'};
    return $logic_name;
}

sub target_start {
    my ($self, @args) = @_;
    ($self->{'target_start'}) = @args if @args;
    my $target_start = $self->{'target_start'};
    return $target_start;
}

sub command {
    my ($self, @args) = @_;
    ($self->{'command'}) = @args if @args;
    my $command = $self->{'command'};
    return $command;
}

sub fingerprint {
    my ($self, @args) = @_;
    ($self->{'fingerprint'}) = @args if @args;
    my $fingerprint = $self->{'fingerprint'};
    return $fingerprint;
}

sub status {
    my ($self, @args) = @_;
    ($self->{'status'}) = @args if @args;
    my $status = $self->{'status'};
    return $status;
}

sub n_hits {
    my ($self, @args) = @_;
    ($self->{'n_hits'}) = @args if @args;
    my $n_hits = $self->{'n_hits'};
    return $n_hits;
}

sub is_stored {
    my ($self, @args) = @_;
    ($self->{'is_stored'}) = @args if @args;
    my $is_stored = $self->{'is_stored'};
    return $is_stored;
}

sub args {
    my ($self, @args) = @_;
    ($self->{'args'}) = @args if @args;
    my $args = $self->{'args'};
    return $args;
}

sub missed_hits {
    my ($self, @args) = @_;
    ($self->{'missed_hits'}) = @args if @args;
    my $missed_hits = $self->{'missed_hits'};
    return $missed_hits;
}

sub transcript_id {
    my ($self, @args) = @_;
    ($self->{'transcript_id'}) = @args if @args;
    my $transcript_id = $self->{'transcript_id'};
    return $transcript_id;
}

sub caller_ref {
    my ($self, @args) = @_;
    ($self->{'caller_ref'}) = @args if @args;
    my $caller_ref = $self->{'caller_ref'};
    return $caller_ref;
}

sub raw_result {
    my ($self, @args) = @_;
    ($self->{'raw_result'}) = @args if @args;
    my $raw_result = $self->{'raw_result'};
    return $raw_result;
}

# These two are exonerate-specific
#
sub query_file {
    my ($self) = @_;
    return $self->args->{'--query'};
}

sub target_file {
    my ($self) = @_;
    return $self->args->{'--target'};
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::DB::OTFRequest

=head1 DESCRIPTION

Represents the state of an OTF request as stored
in the otter_otf_request table in the SQLite db.

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

# EOF
