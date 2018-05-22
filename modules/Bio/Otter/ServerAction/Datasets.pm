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
