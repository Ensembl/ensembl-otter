
### Bio::Otter::RequestQueuer

package Bio::Otter::RequestQueuer;

use strict;
use warnings;

use Log::Log4perl;
use Readonly;
use Scalar::Util 'weaken';

Readonly my $MAX_REQUESTS => 4;

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

    my @to_send;
    while ($self->_slots_available and $self->_queue_not_empty) {
        my $current = shift @$queue;
        push @to_send, $current;
        $self->_current_request($current, $current);
        # TODO: column status
    }

    if (@to_send) {
        $self->_logger->debug("_send_queued_requests: loading '", join(',', @to_send), "', ", scalar(@$queue), " remaining");
        $self->session->zmap->load_features(@to_send);
    } else {
        $self->_logger->debug("_send_queued_requests: nothing to send, ", scalar(@$queue) ? 'no slots' : 'queue empty');
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
    my $available = $MAX_REQUESTS - $n_current;
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
