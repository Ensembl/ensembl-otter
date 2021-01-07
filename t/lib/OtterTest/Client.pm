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

# Dummy B:O:Lace::Client

package OtterTest::Client;

use strict;
use warnings;

use Bio::Otter::Server::Config;
use Bio::Otter::Server::Support::Local;
use Bio::Otter::ServerAction::AccessionInfo;
use Bio::Otter::ServerAction::Config;
use Bio::Otter::ServerAction::Datasets;
use Bio::Otter::ServerAction::LoutreDB;
use Bio::Otter::ServerAction::XML::Region;
use Bio::Otter::Version;

use Carp;
use File::Slurp qw( slurp write_file );
use JSON;
use Test::Builder;
use Try::Tiny;

use parent 'Bio::Otter::Lace::Client';

# For caution, we deliberately black-list methods we have not decided to allow or override
# This doesn't necessarily mean they cannot be used, just that they have yet to be inspected.
BEGIN {
    my @blacklist = qw(
        the
        write_access
        author
        email
        no_user_config
        get_log_dir
        make_log_file
        cleanup
        all_session_dirs
        new_AceDatabase
        client_hostname
        chr_start_end_from_contig
        password_prompt
        password_problem
        reauthorize_if_cookie_will_expire_soon
        config_set
        get_UserAgent
        env_config
        get_CookieJar
        url_root
        url_root_is_default
        pfetch_url
        otter_response_content
        http_response_content
        status_refresh_for_DataSet_SequenceSet
        find_clones
        lock_refresh_for_DataSet_SequenceSet
        fetch_all_SequenceNotes_for_DataSet_SequenceSet
        change_sequence_note
        push_sequence_note
        get_server_otter_config
        designate_this
        get_slice_DE
        do_authentication
        get_all_SequenceSets_for_DataSet
        get_all_CloneSequences_for_DataSet_SequenceSet
        save_otter_xml
        config_value_list
        config_value_list_merged
        config_section
        config_keys
        sessions_needing_recovery
        recover_session
        lock_region
        unlock_region
        );
    foreach my $method ( @blacklist ) {
        my $sub = sub {
            confess "Client->${method}() blacklisted in OtterTest.\nYou should inspect it before allowing or overriding.\n";
        };
        no strict 'refs';
        *{$method} = $sub;
    }
}

sub new {
    my ($pkg) = @_;
    return bless {}, $pkg;
}

sub _local_server {
    my $self = shift;
    return $self->{_local_server} ||= Bio::Otter::Server::Support::Local->new;
}

sub get_accession_types {
    my ($self, @accessions) = @_;
    $self->_local_server->set_params(accessions => \@accessions);
    my $response = $self->_s_a_accession_info->get_accession_types;
    return $response;
}

sub get_taxonomy_info {
    my ($self, @taxon_ids) = @_;
    $self->_local_server->set_params(id => \@taxon_ids);
    my $response = $self->_s_a_accession_info->get_taxonomy_info;
    return $response;
}

sub _s_a_accession_info {
    my $self = shift;
    return $self->{_s_a_accession_info} ||= Bio::Otter::ServerAction::AccessionInfo->new($self->_local_server);
}

# Overrides private method in B:O:L:Client.
# We choose not to cache, despite the name.
#
# Provides:
#   get_otter_styles
#   get_otter_schema
#   get_loutre_schema
#   get_server_ensembl_version
#   get_methods_ace
#
sub _get_cache_config_file {
    my ($self, $key) = @_;
    my $_local_server = $self->_local_server;
    $_local_server->set_params(key => $key);
    return Bio::Otter::ServerAction::Config->new($_local_server)->get_config;
}

sub get_meta {
    my ($self, $dsname) = @_;
    return $self->_cached_loutre_db_response('get_meta', $dsname);
}

sub get_db_info {
    my ($self, $dsname) = @_;
    return $self->_cached_loutre_db_response('get_db_info', $dsname);
}

sub _get_DataSets_hash {
    my ($self) = @_;
    return Bio::Otter::ServerAction::Datasets->new($self->_local_server)->get_datasets;
}

{
    my %_config_hash;

    sub config_section_value {
        my ($self, $section, $key) = @_;
        return $_config_hash{$section}->{$key};
    }

    # NOT A METHOD
    sub Set_Config {
        my ($config) = @_;
        %_config_hash = ( %$config );
        return;
    }
}

sub get_region_xml {
    my ($self, $slice) = @_;
    my $_local_server = $self->_local_server;
    $_local_server->set_params($self->slice_query($slice));
    return Bio::Otter::ServerAction::XML::Region->new_with_slice($_local_server)->get_region;
}

sub get_assembly_dna {
    my ($self, $slice) = @_;
    my $_local_server = $self->_local_server;
    $_local_server->set_params($self->slice_query($slice));

    my $raw = Bio::Otter::ServerAction::Region->new_with_slice($_local_server)->get_assembly_dna;
    return $raw->{dna};
}

sub _cached_loutre_db_response {
    my ($self, $what, $dsname) = @_;

    my $tb = Test::Builder->new;

    my $fn = $self->_response_cache_fn($what, $dsname);
    my $cache_age = 1; # days

    my $response;
    if (-f $fn && (-M _) < $cache_age) {
        # got it, and it's recent
        $response = slurp($fn);
    } else {
        # probably need to fetch it
        my $error;
        ($error, $response) = $self->_get_fresh_loutre_db_json($what, $dsname, $fn);
        if ($error && -f $fn) {
            my $age = -M $fn;
            $tb->diag("Proceeding with $age-day stale $fn because cannot fetch fresh ($error)");
            $response = slurp($fn);
        } elsif ($error) {
            die "No cached data at $fn ($error)";
        }
    }

    return $self->_decode_json($response);
}

sub _get_fresh_loutre_db_json {
    my ($self, $what, $dsname, $fn) = @_;

    my ($error, $response);
    try {
        my $tb = Test::Builder->new;

        my $_local_server = $self->_local_server;
        $_local_server->set_params(dataset => $dsname);

        my $ldb = Bio::Otter::ServerAction::LoutreDB->new($_local_server);
        $response = $ldb->$what;
        $tb->note("OtterTest::Client::$what: fetched fresh copy");

        $response = $self->_encode_json($response);

        write_file($fn, \$response);
        $tb->note("OtterTest::Client::$what: cached in '$fn'");

        1;
    }
    catch {
        $error = $_;
    };
    return ($error, $response);
}

sub _response_cache_fn {
    my ($self, $what, $dsname) = @_;
    my $fn = __FILE__; # this module
    my $pkgfn = __PACKAGE__;
    $pkgfn =~ s{::}{/}g;
    my $vsn = Bio::Otter::Version->version;
    $fn =~ s{((?:^|/)t/)lib/\Q${pkgfn}.pm\E$}{$1.OTC.${what}_response.${vsn}.${dsname}.txt}
      or die "Can't make filename from $fn";
    return $fn;
}

{
    my $json;

    sub _json {
        my ($self) = @_;
        return $json ||= JSON->new->pretty;
    }

    sub _encode_json {
        my ($self, $raw) = @_;
        return $self->_json->encode($raw);
    }

    sub _decode_json {
        my ($self, $encoded) = @_;
        return $self->_json->decode($encoded);
    }
}

1;
