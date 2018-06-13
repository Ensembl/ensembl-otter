=head1 LICENSE

Copyright [2018] EMBL-European Bioinformatics Institute

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

package Bio::Otter::ServerAction::Test;
use strict;
use warnings;

use DBI;
use File::Find;
use Try::Tiny;
use Sys::Hostname 'hostname';
use Cwd 'cwd';
use Digest::SHA 'sha1_hex';
use YAML 'Dump';

use Bio::Otter::Server::Support::Web;
use Bio::Otter::Version;
use Bio::Otter::Git;
use Bio::Otter::Auth::SSO;
use Bio::Otter::Utils::RequireModule qw(require_module);

use Bio::EnsEMBL::ApiVersion ();

use base 'Bio::Otter::ServerAction';

sub as_yaml {
    my ($self) = @_;

    return "You are an external user\n" unless $self->server->local_user;

    my %out = $self->generate;
    return Dump(\%out);
}


# keep the align-to-centre layout, it's easier to read than YAML
sub __hash2table {
    my ($hashref) = @_;
    my $out;
    foreach my $var (sort keys %$hashref) {
        $out .= sprintf "%35s  %s\n", $var,
          defined $hashref->{$var} ? $hashref->{$var} : '(undef)';
    }
    return $out;
}

# load all our modules, and their deps
sub _require_all {
    my $dir = __FILE__;
    $dir =~ s{Otter/\w+/\w+\.pm$}{}
      or die "Cannot reconstruct dir from $dir";

    # some modules need a clean PATH
    $ENV{PATH} = '/bin:/usr/bin';

    my @mods;
    my $wanted = sub {
        if (-f && m{.*/(modules|\d+)/(Bio/.*)\.pm$}) {
            my $modfn = $2; # untainted
            $modfn =~ s{/}{::}g;
            push @mods, $modfn;
        }
        return ();
    };
    find({ wanted => $wanted, no_chdir => 1 }, $dir);

    # Safety check - we want Bio::Otter and Bio::Vega,
    # but not the entire Perl
    my $n = @mods;
    die "Expected 100 - 300 modules, now looking at $n"
      if $n < 100 || $n > 300;

    my %out;
    foreach my $mod (@mods) {
        my $err;
        if (require_module($mod, error_ref => \$err)) {
            push @{ $out{loaded} }, $mod;
        } else {
            $err =~ s{ \(\@INC contains: [^()]+\) at }{... at };
            $out{error}->{$mod} = $err;
        }
    }

    return \%out;
}

sub _code_sums {
    my %out;
    while (my ($mod, $fn) = each %INC) {
        if (!defined $fn) {
            $out{$mod} = undef;
        } elsif (open my $fh, '<', $fn) {
            my $txt = do { local $/ = undef; <$fh> };
            $out{$mod} = sha1_hex($txt);
        } else {
            $out{$mod} = "$fn: $!";
        }
    }
    return \%out;
}

sub _is_SangerWeb_real {
    my $src = $INC{'SangerWeb.pm'};
    if (!defined $src) {
        return 'None (?!)';
    } elsif (SangerWeb->can('is_dev') && $SangerWeb::VERSION) {
        return "Genuine $SangerWeb::VERSION from $src";
    } else {
        return "Bogus from $src";
    }
}


sub generate {
    my ($self) = @_;
    my $server = $self->server;
    my $web = $server->sangerweb;

    my $user = $web->username;

    my %out = (ENV => __hash2table(\%ENV),
               best_client_hostname => [ $server->best_client_hostname(1) ],
               CGI_param => '');

    foreach my $var ($server->param) {
        $out{CGI_param} .= sprintf "%24s  %s\n", $var, $server->param($var);
    }

    $out{Path_info} = $server->path_info;

    # avoiding exposing internals (private or verbose)
    my $cgi = $web->cgi;
    $out{SangerWeb} = { cgi => "$cgi",
                        origin => _is_SangerWeb_real(),
                        HTTP_CLIENTREALM => $ENV{HTTP_CLIENTREALM},
                        username =>  $web->username };

    $out{webserver} =
      { hostname => scalar hostname(),
        user => scalar getpwuid($<),
        group => [ map { "$_: ".getgrgid($_) } split / /, $( ],
        cwd => scalar cwd(),
        pid => $$ };

    $out{'B:O:Server::Support::Web'} =
      { local_user => $server->local_user,
#        BOSSS => $server, # would leak users config & CGI internals
        internal_user => $server->internal_user };

    foreach my $mod ('Bio::Otter::Auth::SSO',
                     # 'Bio::Otter::Auth::Pagesmith', # broken, deleted
                    ) {
        $out{ $mod->test_key } = { $mod->auth_user($web, $server->Access) };
    }

    $out{'B:O:Server::Config'} =
      { data_dir => Bio::Otter::Server::Config->data_dir,
        data_filename => { root => [ Bio::Otter::Server::Config->data_filename('foo') ],
                           vsn => [ Bio::Otter::Server::Config->data_filename(foo => 1) ] },
        mid_url_args => Bio::Otter::Server::Config->mid_url_args,
        designations => Bio::Otter::Server::Config->designations };

    $out{version} =
      { major => Bio::Otter::Version->version,
        '$^X' => $^X, '$]' => $],
        CACHE => $Bio::Otter::Git::CACHE,
        ensembl_api => Bio::EnsEMBL::ApiVersion::software_version(),
        ensembl_from => $INC{'Bio/EnsEMBL/ApiVersion.pm'},
        otter_from => __FILE__,
        otter_origin => $INC{'Bio/Otter/Git/Cache.pm'} ? 'build' : 'clone',
      };
    $out{version}{code} = try { Bio::Otter::Git->as_text } catch { "FAIL: $_" };

    my $db = 'otp1_slave';
    my $otp1_slave = try { Bio::Otter::Server::Config->Database($db) };
    if ($otp1_slave) {
        my $h = $otp1_slave->host;
        my $p = $otp1_slave->port;
        my $dbh = DBI->connect
      ("DBI:mysql:database=pipe_human;host=${h};port=${p}",
       "ottro", undef, { RaiseError => 0 });
        $out{DBI} = $dbh ? { connected => "$dbh" } : { error => DBI->errstr };
    } else {
        $out{DBI} = { error => "'$db' not found via BOS:Config->Database()" };
    }

    if ($server->param('load')) {
        $out{load_modules} = _require_all();
    }

    if ($server->param('more')) {
        $out{Perl} =
          { '${^TAINT}' => ${^TAINT},
            '@INC' => \@INC, '%INC' => __hash2table(\%INC),
            '%INC_sum' => _code_sums(),
          };
    }

    return %out;
}


1;

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut
