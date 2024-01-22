=head1 LICENSE

Copyright [2018-2024] EMBL-European Bioinformatics Institute

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
