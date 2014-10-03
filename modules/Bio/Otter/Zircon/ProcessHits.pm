
package Bio::Otter::Zircon::ProcessHits;

use strict;
use warnings;

use feature 'switch';

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

    $new->launch_app;
    return $new;
}

sub zircon_trace_prefix {
    my ($self) = @_;
    return 'B:O:Z:ProcessHits';
}

sub process_columns {
    my ($self, @columns) = @_;
    return $self->send_command('process', undef, [ columns => {}, map { $_->name } @columns ]);
}

sub zircon_server_protocol_command {
    my ($self, $command, $view_id, $request_body) = @_;

    # FIXME: dup with process_hits, Zircon::ZMap (and below, in processed())
    my $tag_entity_hash = { };
    $tag_entity_hash->{$_->[0]} = $_ for @{$request_body};

    for ($command) {

        when ('processed') {
            return $self->processed($tag_entity_hash);
        }

        default {
            my $reason = "Unknown process_hits command: '${command}'";
            return $self->protocol->message_command_unknown($reason);
        }
    }
    return;
}

sub processed {
    my ($self, $tag_entity_hash) = @_;

    my $columns_entity = $tag_entity_hash->{'columns'};
    $columns_entity or die "missing columns entity";
    my (undef, undef, @columns) = @{$columns_entity};
    @columns = grep { $_ } @columns;

    foreach my $column (@columns) {
        warn("processed: '$column'");
    }

    return $self->protocol->message_ok('got processed, thanks.');
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
