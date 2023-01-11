=head1 LICENSE

Copyright [2018-2023] EMBL-European Bioinformatics Institute

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


package Bio::Otter::Zircon::ProcessHits;

use strict;
use warnings;

use Readonly;
use Scalar::Util 'weaken';

use parent qw(
    Zircon::Protocol::Server::AppLauncher
    Bio::Otter::Log::WithContextMixin
);

our $ZIRCON_TRACE_KEY = 'ZIRCON_PROCESS_HITS_TRACE';

sub new {
    my ($pkg, %arg_hash) = @_;
    my $new = $pkg->SUPER::new(
        -program         => 'process_hits',
        -app_tag         => 'otter_hits',
        -serialiser      => 'JSON',
        -peer_socket_opt => 'peer_socket',
        %arg_hash,
        );
    $new->_session_window(    $arg_hash{'-session_window'});
    $new->_processed_callback($arg_hash{'-processed_callback'});
    $new->_update_callback(   $arg_hash{'-update_callback'});
    $new->log_context(        $arg_hash{'-log_context'});

    $new->_queue([]);

    $new->launch_app;
    return $new;
}

sub zircon_trace_prefix {
    my ($self) = @_;
    return 'B:O:Z:ProcessHits';
}

sub process_columns {
    my ($self, @columns) = @_;
    $self->_queue_columns(@columns);
    $self->_send_queued_column;
    return;
}

sub _queue_columns {
    my ($self, @columns) = @_;
    push @{$self->_queue}, @columns;
    $self->_update_callback->($self->_session_window, $_, 'HitsQueued') foreach @columns;
    $self->logger->debug('Queued: ', join(',', map { $_->name } @columns));
    return;
}

sub _send_queued_column {
    my ($self) = @_;

    if ($self->_busy) {
        $self->logger->debug('_send_queued_column: busy');
        return;
    }

    my $queue = $self->_queue;
    unless (@$queue) {
        $self->logger->debug('_send_queued_column: idle');
        return;
    }

    my $next_col = shift @$queue;
    my $name = $next_col->name;
    $self->logger->debug("_send_queued_column: sending '$name'");

    $self->_busy($next_col);
    $self->_update_callback->($self->_session_window, $next_col, 'HitsProcess');
    $self->send_command('process', undef, [ columns => {}, $name ]);

    return;
}

Readonly my %_dispatch_table => (
    processed => { method => \&_processed, key_entity => qw( columns ) },
    );

sub command_dispatch {
    my ($self, $command) = @_;
    return $_dispatch_table{$command};
}

sub _processed {
    my ($self, $view_handler, $columns_entity) = @_;

    my (undef, undef, @columns) = @{$columns_entity};
    @columns = grep { $_ } @columns;

    foreach my $column (@columns) {

        unless ($self->_busy) {
            $self->logger->warn("not expecting a processed message for '$column'");
            next;
        }

        $self->logger->debug("_processed: '$column'");
        my $expected = $self->_busy;
        if ($column ne $expected->name) {
            $self->logger->warn ("got processed message for '$column', but expected '", $expected->name, "'");
            next;
        }

        $self->_processed_callback->($self->_session_window, $expected);
        $self->_busy(undef);
    }

    $self->protocol->connection->after( sub { $self->_send_queued_column } );

    return $self->protocol->message_ok('got processed, thanks.');
}

sub _queue {
    my ($self, @args) = @_;
    ($self->{'_queue'}) = @args if @args;
    my $_queue = $self->{'_queue'};
    return $_queue;
}

sub _busy {
    my ($self, @args) = @_;
    ($self->{'_busy'}) = @args if @args;
    my $_busy = $self->{'_busy'};
    return $_busy;
}

sub _session_window {
    my ($self, @args) = @_;
    if (@args) {
        ($self->{'_session_window'}) = @args if @args;
        weaken $self->{'_session_window'};
    }
    my $_session_window = $self->{'_session_window'};
    return $_session_window;
}

sub _processed_callback {
    my ($self, @args) = @_;
    ($self->{'_processed_callback'}) = @args if @args;
    my $_processed_callback = $self->{'_processed_callback'};
    return $_processed_callback;
}

sub _update_callback {
    my ($self, @args) = @_;
    ($self->{'_update_callback'}) = @args if @args;
    my $_update_callback = $self->{'_update_callback'};
    return $_update_callback;
}

sub default_log_context {
    return '-B-O-Z-ProcessHits unnamed-';
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
