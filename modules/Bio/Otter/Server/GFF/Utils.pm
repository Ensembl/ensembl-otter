
package Bio::Otter::Server::GFF::Utils;

use strict;
use warnings;

sub db_connect {
    my ($self) = @_;

    my $db_dsn   = $self->require_argument('db_dsn');
    my $db_user  = $self->require_argument('db_user');
    my $db_pass  = $self->param('db_pass');

    my $db_table = $self->require_argument('db_table');
    ($db_table) = $db_table =~ m/(\w+)/; # avoid sql injection

    my $connecting = sprintf("connecting to '%s' %s %s, table %s\n",
        $db_dsn,
        $db_user ? "as '${db_user}'" : "[no user]",
        $db_pass ? "with pw"         : "[no pw]",
        $db_table);

    my $dbh = DBI->connect($db_dsn, $db_user, $db_pass, {RaiseError => 1})
        or die "Error $connecting";

    return ($dbh, $db_table);
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

