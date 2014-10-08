
package Bio::Otter::Zircon::ProcessHits;

use strict;
use warnings;

use Readonly;

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
        warn("processed: '$column'");
    }

    return $self->protocol->message_ok('got processed, thanks.');
}

1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
