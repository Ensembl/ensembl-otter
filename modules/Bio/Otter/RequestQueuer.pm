
### Bio::Otter::RequestQueuer

package Bio::Otter::RequestQueuer;

use strict;
use warnings;

use Log::Log4perl;
use Scalar::Util 'weaken';

sub new {
    my ($pkg, $session) = @_;

    my $self = {
        '_queue'   => [],
        '_session' => $session,
        '_current_request' => undef,
    };
    weaken($self->{_session});

    return bless $self, $pkg;
}

sub queue_features {
    my ($self, @feature_list) = @_;
    push @{$self->_queue}, @feature_list;
    $self->_logger->debug('request_features: queued ', scalar(@feature_list));
    return;
}

sub request_features {
    my ($self, @feature_list) = @_;
    $self->queue_features(@feature_list);
    $self->send_queued_requests;
    return;
}

sub send_queued_requests {
    my ($self) = @_;
    $self->_load_next if $self->idle;
    return;
}

sub features_loaded_callback {
    my ($self, $loaded) = @_;

    my $current_request = $self->_current_request;
    unless ($current_request) {
        $self->_logger->warn("features_loaded_callback: no request in progress, but called for '$loaded'");
        return;
    }
    if ($loaded ne $current_request) {
        $self->_logger->warn("features_loaded_callback: '$loaded' does not match current request '$current_request'");
        return;
    }

    $self->_logger->debug("features_loaded_callback: loaded '$loaded'");
    $self->_current_request(undef);

    $self->_load_next if @{$self->_queue};

    return;
}

sub idle {
    my ($self) = @_;
    if ($self->_current_request) {
        return;
    } else {
        return 1;
    }
}

sub session {
    my ($self, @args) = @_;
    ($self->{'_session'}) = @args if @args;
    my $session = $self->{'_session'};
    return $session;
}

sub _load_next {
    my ($self) = @_;
    my $queue = $self->_queue;

    $self->_logger->logconfess('_load_next: not idle')    unless $self->idle;
    $self->_logger->logconfess('_load_next: queue empty') unless @$queue;

    my $current = $self->_current_request( shift @$queue );
    $self->_logger->debug("_load_next: loading '$current', ", scalar(@$queue), " remaining");
    # TODO: column status
    $self->session->zmap->load_features($current);

    return;
}

sub _queue {
    my ($self) = @_;
    my $_queue = $self->{'_queue'};
    return $_queue;
}

sub _current_request {
    my ($self, @args) = @_;
    ($self->{'_current_request'}) = @args if @args;
    my $_current_request = $self->{'_current_request'};
    return $_current_request;
}

sub _logger {
    return Log::Log4perl->get_logger;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::Source::Collection

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
