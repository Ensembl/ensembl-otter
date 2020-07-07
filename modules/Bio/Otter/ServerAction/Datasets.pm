=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

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

package Bio::Otter::ServerAction::Datasets;

use strict;
use warnings;

use base 'Bio::Otter::ServerAction';

=head1 NAME

Bio::Otter::ServerAction::Datasets - serve dataset list

=cut

# Parent constructor is fine unaugmented.

### Methods

=head2 get_datasets
=cut

# Don't show any mysql connection details to clients Outside.
my %secret_params = map { ( $_ => 1 ) }
  qw{ DBNAME DBSPEC  DNA_DBSPEC DNA_DBNAME };

# DBI params no longer go over HTTP anywhere.  Whitelist the rest.
my %good_params = map { ( $_ => 1 ) }
  qw{ READONLY ALIAS  DBNAME DBSPEC  DNA_DBSPEC DNA_DBNAME };
  # HEADCODE, TYPE, RESTRICTED : obsolete

sub get_datasets {
    my ($self) = @_;
    my $server = $self->server;

    # Only local users get to see mysql connection details
    my $show_details = $server->local_user;

    my $is_local = $server->isa('Bio::Otter::Server::Support::Local');
    my $unauth_user = $self->{'_server'}->{'_authenticated_user'};

    my %datasets;
    foreach my $dataset (@{$server->allowed_datasets($unauth_user)}) {
        my $name   = $dataset->name;
        my $params = $dataset->ds_all_params;

        my %ds;
        foreach my $key (keys %$params) {
            unless ($good_params{$key}) {
                warn "Redacted key=$key - old species.dat?" unless $is_local;
                next;
            }
            unless ($show_details) {
                next if $secret_params{$key};
            }
            my $lckey = lc($key);   ### Why do we bother lower casing this?
            # BOL:Client upcases it, to make property accessor names
            $ds{$lckey} = $params->{$key};
        }

        $datasets{$name} = \%ds;
    }

    return \%datasets;
}


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
