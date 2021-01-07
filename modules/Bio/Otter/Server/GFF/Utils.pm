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

