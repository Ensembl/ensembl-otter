package Bio::Otter::Server::Config;
use strict;
use warnings;

use Carp;
use Data::Rmap     qw(rmap);
use File::Basename ();
use File::Spec     ();
use Hash::Merge::Simple;
use List::MoreUtils qw(uniq);
use Try::Tiny;
# require YAML::Any; # sometimes (below), but it is a little slow

use Bio::Otter::SpeciesDat;
use Bio::Otter::SpeciesDat::Database;
use Bio::Otter::Version;
use Bio::Otter::Auth::Access;
use Bio::Otter::Server::UserSpecies;

=head1 NAME

Bio::Otter::Server::Config - obtain config data for Otter Server

=head1 DESCRIPTION

This module contains only class methods.

=head1 CLASS METHODS

=head2 data_dir()

Return the default Otter Server config directory, as configured with
the webserver or from some "well known" central place.

This does not allow for per-developer configuration override.  See
also L</data_filename> which does.

=cut

sub data_dir {
    my ($pkg) = @_;

    my ($root, $src, $webtree) =
      ($ENV{'DOCUMENT_ROOT'}, '$DOCUMENT_ROOT', 1); # has first priority

    if (!defined $root) {
        # Let client scripts be given explicit config.  RT#398147
        #
        # It must contain the full tree (dev or live branch)
        # not just a root- or version- branch.
        ($root, $src, $webtree) =
          ($ENV{'ANACODE_SERVER_CONFIG'}, '$ANACODE_SERVER_CONFIG', 0);
    } else {
        warn '$ANACODE_SERVER_CONFIG ignored because $DOCUMENT_ROOT was set'
          if defined $ENV{'ANACODE_SERVER_CONFIG'};
    }

    if (!defined $root) {
        # For internal non-web machines, provide the central copy to
        # remove the need to pretend we have DOCUMENT_ROOT .
        #
        # Web machines shouldn't have a fallback, too magical.
        # (They don't have /software/ )
        ($root, $src, $webtree) =
          ("/nfs/anacode/WEBVM_docs.live/htdocs", # DUP also in team_tools pubweblish
           'fallback', 1)
          if -d '/software/anacode';
    }

    die "Cannot find data_dir via DOCUMENT_ROOT, ANACODE_SERVER_CONFIG or fallback"
      unless defined $root;

    my $data = $root;
    if ($webtree) {
        # Trim off the trailing /dir (usually htdocs)
        $data =~ s{/[^/]+$}{}
          or die "Unexpected DOCUMENT_ROOT format '$root' from $src";
        $data = join('/', $data, 'data', 'otter');
        $src .= " near root '$root'";
    }

    die "data_dir $data (from $src): not found"
      unless -d $data;

    my $vsn = Bio::Otter::Version->version;
    my @want = ("species_ens.dat", "access.yaml",
                "$vsn/otter_config", "$vsn/otter_styles.ini");
    my @lack = grep { ! -f "$data/$_" } @want;
    die "data_dir $data (from $src): lacks expected files (@lack)"
      if @lack;

    return $data;
}


=head2 mid_url_args()

Return a hashref of key-value items taken from C<$1> of URL
C<http://server:port/cgi-bin/otter([^/]*)/\d+/\w+>

This is empty in normal production use, and will be empty if the
pattern doesn't match (no errors raised).

In DEVEL mode servers it may be used to point L</data_filename>
elsewhere.  CGI escapes are %-decoded and the result is re-tainted.

=cut

sub mid_url_args {
    my ($pkg) = @_;
    my %out;
    my $retaint = substr("$0$^X",0,0); # CGI.pm 3.49 does this too

    if (!defined $ENV{REQUEST_URI}) {
        # Running outside the normal CGI environment, probably for
        # test & debug purposes.
        #
        # $ANACODE_SERVER_CONFIG could point at config
    } elsif ($ENV{REQUEST_URI} =~ m{^/cgi-bin/otter([^/]*)/\d+(_[^/]+)?/}) {
        # cf. webvm.git apps/50otter.conf ScriptAliasMatch
        # ^/cgi-bin/otter([^/]+)/(\d+(?:_[^/]+)?)/([^/]+)$
        my $mu = $1;
        foreach my $arg (split /;/, $mu) {
            if ($arg =~ m{^~([-a-z0-9]{1,16})$}) {
                # short case for a username, detainted
                $out{'~'} = $1;
            } elsif ($arg =~ m{^([-a-zA-Z0-9_.]+)=(.*)$}) {
                # regex is not intended to de-taint!
                my ($k, $v) = ($1, $2);
                foreach ($k, $v) {
                    s/%([0-9a-f]{2})/chr(hex($1))/eig;
                }
                $out{$k} = $v . $retaint;
            } else {
                warn "mid_url_args($arg): not understood";
            }
        }
    } else {
        warn "No mid_url_args: SCRIPT_NAME mismatch";
    }
    return \%out;
}


# Accept configuration from another user iff they exist and are a
# member of our primary group.
sub _dev_config {
    my ($pkg) = @_;

    if (my $test_devdir = $ENV{ANACODE_SERVER_DEVCONFIG}) {
        # override for test suite
        return $test_devdir;
    }

    my $developer = $pkg->mid_url_args->{'~'};
    return () unless defined $developer;

    my ($dev_home, $dev_group) = (getpwnam($developer))[7, 3];
    die "Developer config for $developer: unknown user" unless defined $dev_home;

    my $ok_group = $(;
    my ($gname, $gmemb) = (getgrgid( $ok_group ))[0, 3];
    my @ok_user = split / /, $gmemb;
    die "Developer config for $developer: not a member of group $gname"
      unless $dev_group == $ok_group || grep { $developer eq $_ } @ok_user;

    my $dir = "$dev_home/.otter/server-config";
    die "Developer config $dir: not a readable directory"
      unless -d $dir && -r _;

    return $dir;
}


=head2 data_filename($fn, $add_vsn)

Return the full pathname of Otter Server Config file C<$fn>, prefixed
with the current major version number if C<$add_vsn> is true.  In list
context, return also the description of the config source.

This method accepts (via L</mid_url_args> containing a C<~username>
element) files from a developer's local configuration, to ease the
process of testing new configuration.

It can return the name of a file which does not exist, or die failing
to obtain configuration.

=cut

sub data_filename {
    my ($pkg, $fn, $add_vsn) = @_;

    my $vsn = Bio::Otter::Version->version;
    $fn =~ s{^/*}{$vsn/} if $add_vsn;

    my $data_dir = $pkg->data_dir;
    my @out;

    # Possible override for testing config
    my $dev_cfg = $pkg->_dev_config;

    $pkg->_assert_private($data_dir);
    $pkg->_assert_private($dev_cfg) if defined $dev_cfg;

    if (!defined $dev_cfg) {
        @out = ("$data_dir/$fn", 'default');
    } elsif (-f "$dev_cfg/species_ens.dat" && -f "$dev_cfg/$vsn/otter_config") {
        @out = ("$dev_cfg/$fn", 'developer (full)');
    } else {
        # We have a partial override, e.g. checkout of a major version
        # branch.  This is needed for cherry-picking but interferes
        # with having neat developer config.
        #
        # Brush the mess under this small carpet.
        my ($want_vsn, $vsn_file) = $fn =~ m{^(\d{2,4})/(.+)$};
        ($want_vsn, $vsn_file) = (root => $fn) unless defined $want_vsn;
        my ($have_vsn, $cfg_branch) = try { __git_head($dev_cfg) }
          catch { die "Examining config from $dev_cfg: $_" };
        if ($have_vsn eq $want_vsn) {
            @out = ("$dev_cfg/$vsn_file",
                    "developer ($have_vsn from $cfg_branch)");
        } else {
            @out = ("$data_dir/$fn",
                    "default; developer checkout is $cfg_branch");
        }
    }
    return wantarray ? @out : $out[0];
}

sub __git_head {
    my ($dir) = @_;
    my $head_fn = "$dir/.git/HEAD";
    open my $fh, '<', $head_fn or die "$!";
    my $txt = <$fh>;
    chomp $txt;
    die "detached HEAD ($txt)" unless $txt =~ m{^ref: (\S+)$};
    my $branch = $1;
    my $vsn;
    if ($branch =~ m{^refs/heads/(root|\d+)$}) {
        # simple branch checkouts
        $vsn = $1;
    } elsif ($branch =~ m{^refs/heads/(?:\w+/)?(root|\d+)-}) {
        # recognisable developer branch
        $vsn = $1;
    } else {
        die "branch name '$branch' does not tell me (major version|root)";
    }
    return ($vsn, $branch);
}

=head2 data_filenames_with_local($fn, $add_vsn)

Returns a list of full pathnames for Otter Server Config file C<$fn>
and its private local siblings.

C<($fn, $add_vsn)> are first expanded to a full path by calling
L<data_filename()>, with any resulting L</mid_url_args> alterations.

If there is a F<.local/> subdirectory adjacent to the config file, and
given that C<$fn> is of the form C<$name.$ext> (for example
F<databases.yaml>),

=over

=item * F<.local/${name}.${ext}> is added to the list if it exists and
is readable.

=item * F<.local/${name}.${OTTER_WEB_STREAM}.${ext}> is added to the
list if the C<OTTER_WEB_STREAM> environment variable is set and the
resulting file exists and is readable.

=back

If no readable files are found, the empty list is returned.

For example, C<data_filenames_with_local('server.yaml')>, with
C<OTTER_WEB_STREAM> set to C<live>, will always return either empty
(if not found) or at least as its first element:

=over

=item * F<${data_dir}/server.yaml> - non-sensitive config

=back

and could also return either or both of:

=over

=item * F<${data_dir}/.local/server.yaml> - private config

=item * F<${data_dir}/.local/server.live.yaml> - stream-specific config

=back

as subsequent elements, in that order.

=cut

sub data_filenames_with_local {
    my ($pkg, $fn, $add_vsn) = @_;

    my $data_filename = $pkg->data_filename($fn, $add_vsn);
    return unless $data_filename;

    my @paths = ( $data_filename );

    my ($name, $data_dir, $ext) = File::Basename::fileparse($data_filename, qr/\.[^.]*?/);
    # NB $ext starts with '.' separator!

    my $local_data_dir = File::Spec->catdir($data_dir, '.local');

    if ( -d $local_data_dir ) {

        $pkg->_assert_private($local_data_dir);

        push @paths, File::Spec->catfile($local_data_dir, "$name$ext");

        if (my $stream = $ENV{OTTER_WEB_STREAM}) {
            push @paths, File::Spec->catfile($local_data_dir, "$name.$stream$ext");
        }
    }

    my @good_paths;
    foreach my $path (@paths) {
        next unless -r $path;
        # this would be nice, but the deployment toolchain needs work to ensure it remains so:
        # $pkg->_assert_private($path);
        push @good_paths, $path;
    }

    return @good_paths;
}

# Directories containing databases.yaml or .git/ with its history must
# not be world readable.
sub _assert_private {
    my ($pkg, $dir) = @_;
    ## no critic (ValuesAndExpressions::ProhibitLeadingZeros) here be octal perms
    my $dmode = (stat($dir))[2] & 07777;
    my $want = $dmode & 07770;
    die sprintf("Insufficient privacy (found mode 0%03o, want 0%03o) on %s",
                $dmode, $want, $dir)
      if $dmode & 0x7;
    return 1;
}


=head2 Databases()

Return a reference to the hash of C<database_key> to
L<Bio::Otter::SpeciesDat::Database> objects from the Otter Server
config directory (since v81).

The collection is cached on the class.

=head2 Database($name)

Return the requested L<Bio::Otter::SpeciesDat::Database> object, or
die.

=cut

my $_DBS;
sub Databases {
    my ($pkg) = @_;
    return $_DBS if defined $_DBS;
    my $dbs = try {
        my ($h) = $pkg->_get_yaml('/databases_ens.yaml');
        $h->{dbspec} or
          die "no dbspec in databases.yaml";
    } catch {
        die "Database passwords not available: $_";
    };
    return $_DBS = Bio::Otter::SpeciesDat::Database->new_many_from_dbspec($dbs);
}

sub Database {
    my ($pkg, $name) = @_;
    my $db = $pkg->Databases->{$name}
      or croak "dbspec{$name} does not exist in databases.yaml";
    return $db;
}

sub databases {
    my ($pkg) = @_;
    warn "deprecated - renamed to match similar"; # one use from webvm.git
    return $pkg->Databases;
}


=head2 SpeciesDat()

Return a fresh instance of L<Bio::Otter::SpeciesDat> from the Otter
Server config directory.

Note that per-user access control has not been applied here, and if it
looks like a webserver is running this will die.

On server, use L<Bio::Otter::Server::Support/allowed_datasets> or
L<Bio::Otter::Server::Support/dataset> instead.

=cut

sub SpeciesDat {
    my ($pkg) = @_;
    confess "Didn't expect to be on a webserver - access control was not promised"
      if (grep { defined $ENV{$_} } qw{ GATEWAY_INTERFACE REQUEST_METHOD }) ||
        ((scalar getpwuid($<)) =~ /www|web/);
    return $pkg->_SpeciesDat;
}

sub _SpeciesDat {
    my ($pkg) = @_;
    my $fn = $pkg->data_filename('/species_ens.dat');
    return Bio::Otter::SpeciesDat->new($fn);
}


=head2 designations()

Return hashref of intended version designations, name to version
number.  Versions may be C<major> or C<major.minor>.

All versions of the code will return the same centrally configured
result, unless some config files are out of sync.

Pointers to clients in various places should match this hash, else
something needs updating.

This replaces the old version controlled F<dist/conf/track> file.

=cut

sub designations {
    my ($pkg) = @_;
    my $fn = $pkg->data_filename('designations.txt');
    return $pkg->_desig($fn);
}

sub _desig {
    my ($pkg, $fn) = @_;
    my %desig;
    open my $fh, '<', $fn
      or die "Error reading version designations $fn: $!";
    while (<$fh>) {
        next if /^\s+$|^#/;
        if (m{^(\S+)\s+(\d+(?:\.\d+)?(?:_\w+)?)$}) {
            $desig{$1} = $2;
        } else {
            warn "Skipped bad version designation $_"
        }
    }
    close $fh;
    return \%desig;
}


=head2 extant_versions()

Consulting L</designations>, return a list of (uniq and ascending)
major version numbers which should exist on the server.

=cut

sub extant_versions {
    my ($called) = @_;
    my $desig = $called->designations;
    my $desig_re = qr{^(\d{2,4})(?:\.\d+)?$};
    my @version = map {
        ## no critic (RegularExpressions::ProhibitCaptureWithoutTest)
        ($desig->{$_} =~ $desig_re
         ? $1 # <-- capture var in test.  Perlcritic bug?
         : die "Didn't understand desig($_ => $desig->{$_}) with $desig_re");
    } keys %$desig;
    @version = uniq(sort {$a <=> $b} @version);

    die unless wantarray;
    return @version;
}


=head2 Access()

Return a L<Bio::Otter::Auth::Access> object, which tells dataset
access for any user.

Currently freshly loaded.  Maybe should be cached.

=cut

my $_access;
sub Access {
    my ($pkg) = @_;
    my $db = $pkg->Databases->{'otter_authentication'};
    my $host = $db->{'_params'}->{'host'};
    my $port = $db->{'_params'}->{'port'};
    my $user = $db->{'_params'}->{'user'};
    my $pass = $db->{'_params'}->{'pass'};
    my $database = 'otter_user_registration';
    my $dsn = "DBI:mysql:$database:$host:$port"; 
    my $acc = Bio::Otter::Server::UserSpecies->species_group($dsn, $user, $pass);
    # this is not caching (like a singleton), it prevents weak refs to
    # the B:O:A:Access vanishing during multi-statement method chains
    $_access = Bio::Otter::Auth::Access->new($acc, $pkg->_SpeciesDat);
    return $_access;
}


=head2 Server()

Returns the Otter Server configuration.

Currently freshly loaded.  Maybe should be cached.

=cut

sub Server {
    my ($pkg) = @_;
    my $conf = $pkg->_get_yaml('/server.yaml');
    return $conf;
}


=head2 get_file($name)

Return the contents of the Otter Server config file C<$name> for the
current major version.

=cut

sub get_file {
    my ($pkg, $name) = @_;

    my $path = $pkg->data_filename($name, 1);
    open my $fh, '<', $path or die "Can't read '$path' : $!";
    local $/ = undef;
    my $content = <$fh>;
    close $fh;

    return $content;
}

=head2 Config substitutions

Three macros are provided for use in YAML config files:

=over

=item __ENV(env_var)__

Replaced with the value of environment variable C<env_var>.

=item __STREAM__

Short-hand for C<__ENV(OTTER_WEB_STREAM)__>.

=item __LOCAL(var)__

The combined config should contain a C<LOCAL> stanza with a definition
for C<var>, which will be substituted for C<__LOCAL(VAR)__>. For
example:

  ---
  LOCAL:
    colour: red
  interface:
    background: __LOCAL(colour)__

will set C<{interface}-E<gt>{background}> to C<red>.

=back

=cut

sub _get_yaml {
    my ($pkg, $name) = @_;
    require YAML::Any;
    my @paths = $pkg->data_filenames_with_local($name);
    my @hashes = map { $pkg->_get_one_yaml($_) } @paths;
    my $conf = Hash::Merge::Simple->merge(@hashes);
    $pkg->_finalise_config($conf);
    return $conf;
}

sub _get_one_yaml {
    my ($pkg, $fn) = @_;
    my @load = YAML::Any::LoadFile($fn);
    die "expected one object in $fn" unless 1 == @load;
    return $load[0];
}

# Nicked from Catalyst::Plugin::ConfigLoader
sub _finalise_config {
    my ($pkg, $conf) = @_;
    Data::Rmap::rmap { $_ = $pkg->_do_substitutions($_, $conf) } $conf;
    return $conf;
}

{
    my %subs = (
        ENV    => \&_subst_from_env,
        LOCAL  => \&_subst_from_local,
        STREAM => sub { shift->_subst_from_env(shift, 'OTTER_WEB_STREAM') },
        );
    my $subsre = join( '|', keys %subs );

    sub _do_substitutions {
        my ($pkg, $value, $conf) = @_;
        return unless $value;

        my ($o_value, $recurs);
        do {
            croak("Recursion limit exceeded for '$value'") if ++$recurs > 20;
            $o_value = $value;
            $value =~
                s{
                  __           # substitutions look like __NAME__ ...
                    ($subsre)  # NAME is  $1
                    (?:        #   ...or optionally
                       \(      #                    like __NAME(args)__
                         (.+?) # args are $2
                       \)
                    )?
                  __
                 }
                 { $subs{ $1 }->( $pkg, $conf, $2 ? split( /,/, $2 ) : () ) }egx;
        } while ($value ne $o_value);

        return $value;
    }

}

sub _subst_from_env {
    my ($pkg, $conf, $v) = @_;
    my $e = $ENV{$v};
    if (defined($e)) {
        return $e;
    } else {
        croak("Missing environment variable: $v");
    }
}

sub _subst_from_local {
    my ($pkg, $conf, $v) = @_;
    my $c_local = $conf->{LOCAL} || croak 'No LOCAL section';
    my $l = $c_local->{$v};
    if (defined($l)) {
        return $l;
    } else {
        croak("Missing local variable: $v");
    }
}

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
