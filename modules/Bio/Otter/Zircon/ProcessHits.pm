
package Bio::Otter::Zircon::ProcessHits;

use strict;
use warnings;

use Readonly;

use Bio::Otter::Log::WithContext;

use parent qw( Zircon::Protocol::Server::AppLauncher );

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
    $new->_processed_callback($arg_hash{'-processed_callback'});
    $new->_update_callback(   $arg_hash{'-update_callback'});
    $new->log_name( $arg_hash{'-log_name'});

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
    $self->_update_callback->($_, 'HitsQueued') foreach @columns;
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
    $self->_update_callback->($next_col, 'HitsProcess');
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

        $self->_processed_callback->($expected);
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

# FIXME: duplication. Provide via a mix-in?
sub logger {
    my ($self, $category) = @_;
    $category = scalar caller unless defined $category;
    return Bio::Otter::Log::WithContext->get_logger($category, name => $self->log_name);
}

sub log_name {
    my ($self, @args) = @_;
    ($self->{'log_name'}) = @args if @args;
    my $log_name = $self->{'log_name'};
    return $log_name || '-B-O-Z-ProcessHits unnamed-';
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
