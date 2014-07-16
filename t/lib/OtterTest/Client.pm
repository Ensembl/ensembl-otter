# Dummy B:O:Lace::Client

package OtterTest::Client;

use strict;
use warnings;

use Bio::Otter::Lace::Client;   # _build_meta_hash
use Bio::Otter::Server::Config;
use Bio::Otter::Server::Support::Local;
use Bio::Otter::ServerAction::AccessionInfo;
use Bio::Otter::ServerAction::TSV::LoutreDB;
use Bio::Otter::Version;

use File::Slurp qw( slurp write_file );
use Test::Builder;
use Try::Tiny;

sub new {
    my ($pkg) = @_;
    return bless {}, $pkg;
}

sub local_server {
    my $self = shift;
    return $self->{_local_server} ||= Bio::Otter::Server::Support::Local->new;
}

sub get_accession_types {
    my ($self, @accessions) = @_;
    $self->local_server->set_params(accessions => \@accessions);
    my $response = $self->sa_accession_info->get_accession_types;
    return $response;
}

sub get_taxonomy_info {
    my ($self, @taxon_ids) = @_;
    $self->local_server->set_params(id => \@taxon_ids);
    my $response = $self->sa_accession_info->get_taxonomy_info;
    return $response;
}

sub sa_accession_info {
    my $self = shift;
    return $self->{_sa_accession_info} ||= Bio::Otter::ServerAction::AccessionInfo->new($self->local_server);
}

# FIXME: scripts/apache/get_config needs reimplementing with a Bio::Otter::ServerAction:: class,
#        which we can then use here rather than duplicating the file names.
#
sub get_otter_schema {
    my $self = shift;
    return Bio::Otter::Server::Config->get_file('otter_schema.sql');
}

sub get_loutre_schema {
    my $self = shift;
    return Bio::Otter::Server::Config->get_file('loutre_schema_sqlite.sql');
}

sub get_meta {
    my ($self, $dsname) = @_;
    my $response = $self->_cached_response_tsv('get_meta', $dsname);
    return $self->Bio::Otter::Lace::Client::_build_meta_hash($response);
}

sub get_db_info {
    my ($self, $dsname) = @_;
    return $self->_cached_response_json('get_db_info', $dsname);
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

sub _cached_response_tsv {
    my ($self, $what, $dsname) = @_;
    return $self->_cached_response($what, $dsname, \&_get_fresh_tsv);
}

sub _cached_response_json {
    my ($self, $what, $dsname) = @_;
    return $self->_cached_response($what, $dsname, \&_get_fresh_json, \&_decode_json);
}

sub _cached_response {
    my ($self, $what, $dsname, $get_fresh_sub, $decode_sub) = @_;

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
        ($error, $response) = $self->$get_fresh_sub($what, $dsname, $fn);
        if ($error && -f $fn) {
            my $age = -M $fn;
            $tb->diag("Proceeding with $age-day stale $fn because cannot fetch fresh ($error)");
            $response = slurp($fn);
        } elsif ($error) {
            die "No cached data at $fn ($error)";
        }
    }

    return $response unless $decode_sub;
    return $self->$decode_sub($response);
}

sub _get_fresh_tsv {
    my ($self, $what, $dsname, $fn) = @_;
    return $self->_get_fresh($what, $dsname, $fn, 'Bio::Otter::ServerAction::TSV::LoutreDB');
}

sub _get_fresh_json {
    my ($self, $what, $dsname, $fn) = @_;
    return $self->_get_fresh($what, $dsname, $fn, 'Bio::Otter::ServerAction::LoutreDB', \&_encode_json);
}

sub _get_fresh {
    my ($self, $what, $dsname, $fn, $ldb_class, $encode_sub) = @_;

    my ($error, $response);
    try {
        my $tb = Test::Builder->new;

        my $local_server = $self->local_server;
        $local_server->set_params(dataset => $dsname);

        my $ldb_tsv = $ldb_class->new($local_server);
        $response = $ldb_tsv->$what;
        $tb->note("OtterTest::Client::$what: fetched fresh copy");

        $response = $self->$encode_sub($response) if $encode_sub;

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
    $fn =~ s{(/t/)lib/\Q${pkgfn}.pm\E$}{$1.OTC.${what}_response.${vsn}.${dsname}.txt}
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
