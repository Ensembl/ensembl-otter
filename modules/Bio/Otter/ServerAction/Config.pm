package Bio::Otter::ServerAction::Config;

use strict;
use warnings;

use Bio::Otter::Server::Config;

use base 'Bio::Otter::ServerAction';

=head1 NAME

Bio::Otter::ServerAction::Config - serve config files and info

=cut

# Parent constructor is fine unaugmented.

### Methods

=head2 get_config
=cut

my %PERMITTED = (
    loutre_schema  => { filename => 'loutre_schema_sqlite.sql' },
    methods_ace    => { filename => 'methods.ace'      },
    otter_config   => { filename => 'otter_config'     },
    otter_schema   => { filename => 'otter_schema.sql' },
    otter_styles   => { filename => 'otter_styles.ini' },
    designations   => { code => \&_designations, content_type => 'application/json' },
    ensembl_version => { code => \&_ens_version },
);

sub get_config {
    my ($self) = @_;
    my $server = $self->server;

    my $key = $server->require_argument('key');

    my $spec = $PERMITTED{$key};
    die "No such config '$key'" unless $spec;

    my $content_type = $spec->{content_type};
    $server->content_type($content_type) if $content_type;

    if ($spec->{filename}) {
        return Bio::Otter::Server::Config->get_file($spec->{filename});
    } elsif ($spec->{code}) {
        return $spec->{code}->();
    } else {
        die "Bad spec '$key'";
    }
}

sub _ens_version {
    require Bio::EnsEMBL::ApiVersion;
    return Bio::EnsEMBL::ApiVersion::software_version()."\n";
}

sub _designations {
    return Bio::Otter::Server::Config->designations;
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
