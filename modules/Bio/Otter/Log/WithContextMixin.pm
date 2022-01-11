=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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


package Bio::Otter::Log::WithContextMixin;

use strict;
use warnings;

use Carp;

use Bio::Otter::Log::WithContext;

=head1 NAME

Bio::Otter::Log::WithContextMixin - provide context-labelled logger() method

=head1 SYNOPSIS

 package Bio::Otter::Useful;
 use parent qw( Bio::Otter::Log::WithContextMixin );

 sub default_log_context(return '-B-O-Useful-not-set-');

 $self->logger->warn('warning will have context');

 package Bio::Otter::UsesUseful;

 my $useful = Bio::Otter::Useful->new;
 $useful->log_context('human clone 2');

C<2014/04/25 16:13:45 Bio.Otter.Useful WARN [human clone 2]: warning will have context>

=head1 DESCRIPTION

A role mixin to provide a L<Bio::Otter::Log::WithContext> logger()
method to the consuming class, where the context can be set
per-object. This allows the context to be logged with every log
message, without having to pass it on each call.

=head1 PROVIDED METHODS

=head2 logger()

The logger object, see L<Log::Log4perl>.

=cut

sub logger {
    my ($self, $category) = @_;
    $category = scalar caller unless defined $category;
    return Bio::Otter::Log::WithContext->get_logger($category, name => $self->log_context);
}

=head2 log_context()

Read/write accessor for the context to be inserted into log
messages. The initial default is provided by the consumer's C<default_log_context()> method.

The consumer can override C<log_context()> if necessary.

The consumer b<must> override C<log_context()> if consumer objects are not blessed hashrefs.

=cut

sub log_context {
    my ($self, @args) = @_;
    ($self->{'log_context'}) = @args if @args;

    $self->{'log_context'} //= $self->default_log_context;

    my $log_context = $self->{'log_context'};
    return $log_context;
}

=head2 default_log_context()

Must be provided by the consumer, unless the consumer overrides C<log_context()>.
Provides the default value for C<log_context()>.
=cut

sub default_log_context {
    confess "default_log_context() must be provided by consumer class [or log_context must be over-ridden].";
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
