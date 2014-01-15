
### Bio::Otter::RequestQueuer

package Bio::Otter::RequestQueuer;

use strict;
use warnings;

use Log::Log4perl;
use Readonly;
use Scalar::Util qw{ weaken };
use Try::Tiny;

Readonly my $MAX_CONCURRENT_REQUESTS => 10;
Readonly my $REQUEST_MIN_BATCH_SIZE  => 4;

sub new {
    my ($pkg, $session) = @_;

    my $self = {
        '_queue'   => [],
        '_session' => $session,
        '_current_requests' => {},
    };
    weaken($self->{_session});

    return bless $self, $pkg;
}

sub request_features {
    my ($self, @feature_list) = @_;
    $self->_queue_features(@feature_list);
    $self->_send_queued_requests;
    return;
}

sub _queue_features {
    my ($self, @feature_list) = @_;
    push @{$self->_queue}, @feature_list;
    $self->_logger->debug('_queue_features: queued ', scalar(@feature_list));
    return;
}

sub _send_queued_requests {
    my ($self) = @_;
    my $queue = $self->_queue;

    my $slots = $self->_slots_available;
    if ($slots < $REQUEST_MIN_BATCH_SIZE) {
        # This is only really required to avoid excessive interleaving in Zircon :-(
        $self->_logger->debug("_send_queued_requests: min batch size not reached");
        return;
    }

    my @to_send;
    while ($self->_slots_available and $self->_queue_not_empty) {
        my $current = shift @$queue;
        push @to_send, $current;
        $self->_current_request($current, $current);
        # TODO: column status
    }

    if (@to_send) {
        my $to_send_debug = join(',', @to_send);
        $self->_logger->debug("_send_queued_requests: requesting '${to_send_debug}', ", scalar(@$queue), " remaining");

        try {
            $self->session->zmap->load_features(@to_send);
        }
        catch {
            my $err = $_;
            my $requeue;
            $requeue = 'busy connection' if $err =~ /Zircon: busy connection/;
            $requeue = 'send_command_and_xml timeout' if $err =~ /send_command_and_xml: timeout/;
            if ($requeue) {
                $self->_logger->warn(
                    "_send_queued_requests: load_features Zircon request failed [$requeue], requeuing '${to_send_debug}'");
                $self->_clear_request($_) foreach @to_send;
                unshift @$queue, @to_send;
            } else {
                die $err;
            }
        };

    } else {
        $self->_logger->debug("_send_queued_requests: nothing to send, ",
                              scalar(@$queue) ? 'no slots' : 'queue empty');
    }

    return;
}

sub features_loaded_callback {
    my ($self, @loaded_features) = @_;

    foreach my $loaded (@loaded_features) {
        my $current_request = $self->_current_request($loaded);
        unless ($current_request) {
            $self->_logger->warn("features_loaded_callback: no request in progress for '$loaded'");
            next;
        }

        $self->_logger->debug("features_loaded_callback: loaded '$loaded'");
        $self->_clear_request($loaded);
    }
    $self->_send_queued_requests;
    return;
}

sub _slots_available {
    my ($self) = @_;
    my $n_current = scalar keys %{$self->{_current_requests}};
    my $available = $MAX_CONCURRENT_REQUESTS - $n_current;
    $available = 0 if $available < 0;
    return $available;
}

sub session {
    my ($self, @args) = @_;
    ($self->{'_session'}) = @args if @args;
    my $session = $self->{'_session'};
    return $session;
}

sub _queue {
    my ($self) = @_;
    my $_queue = $self->{'_queue'};
    return $_queue;
}

sub _queue_not_empty {
    my ($self) = @_;
    return @{$self->_queue};
}

sub _current_request {
    my ($self, $feature, @args) = @_;
    ($self->{'_current_requests'}->{$feature}) = @args if @args;
    my $_current_request = $self->{'_current_requests'}->{$feature};
    return $_current_request;
}

sub _clear_request {
    my ($self, $feature) = @_;
    return delete $self->{'_current_requests'}->{$feature};
}

sub _logger {
    return Log::Log4perl->get_logger;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::Source::Collection

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
