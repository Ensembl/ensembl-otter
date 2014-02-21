# Dummy B:O:Lace::Client

package OtterTest::Client;

use strict;
use warnings;

use Bio::Otter::Lace::Client;   # _build_meta_hash
use Bio::Otter::Utils::MM;
use Bio::Otter::Server::Config;
use Bio::Otter::Server::Support::Local;
use Bio::Otter::ServerAction::TSV::LoutreDB;
use Bio::Otter::Version;

use File::Slurp qw( slurp write_file );
use Test::Builder;
use Try::Tiny;

sub new {
    my ($pkg) = @_;
    return bless {}, $pkg;
}

sub get_accession_types {
    my ($self, @accessions) = @_;
    my $types = $self->mm->get_accession_types(\@accessions);
    # FIXME: de-serialisation is in wrong place: shouldn't need to serialise here.
    # see apache/get_accession_types and AccessionTypeCache.
    my $response = '';
    foreach my $acc (keys %$types) {
        $response .= join("\t", $acc, @{$types->{$acc}}) . "\n";
    }
    return $response;
}

sub mm {
    my $self = shift;
    return $self->{_mm} ||= Bio::Otter::Utils::MM->new;
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
    my $response = $self->_cached_response('get_meta', $dsname);
    return $self->Bio::Otter::Lace::Client::_build_meta_hash($response);
}

sub get_db_info {
    my ($self, $dsname) = @_;
    my $response = $self->_cached_response('get_db_info', $dsname);
    return $self->Bio::Otter::Lace::Client::_build_db_info_hash($response);
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

sub _cached_response {
    my ($self, $what, $dsname) = @_;

    my $tb = Test::Builder->new;

    my $fn = $self->_response_cache_fn($what, $dsname);
    my $cache_age = 1; # days

    if (-f $fn && (-M _) < $cache_age) {
        # got it, and it's recent
        my $response = slurp($fn);
        return $response;
    } else {
        # probably need to fetch it
        my ($error, $response) = $self->_get_fresh($what, $dsname, $fn);
        if ($error && -f $fn) {
            my $age = -M $fn;
            $tb->diag("Proceeding with $age-day stale $fn because cannot fetch fresh ($error)");
            $response = slurp($fn);
        } elsif ($error) {
            die "No cached data at $fn ($error)";
        }
        return $response;
    }
}

sub _get_fresh {
    my ($self, $what, $dsname, $fn) = @_;

    my ($error, $tsv);
    try {
        my $tb = Test::Builder->new;

        my $local_server = Bio::Otter::Server::Support::Local->new;
        $local_server->set_params(dataset => $dsname);

        my $ldb_tsv = Bio::Otter::ServerAction::TSV::LoutreDB->new($local_server);
        $tsv = $ldb_tsv->$what;
        $tb->note("OtterTest::Client::$what: fetched fresh copy");

        write_file($fn, \$tsv);
        $tb->note("OtterTest::Client::$what: cached in '$fn'");

        1;
    }
    catch {
        $error = $_;
    };
    return ($error, $tsv);
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

1;
