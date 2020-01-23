=head1 LICENSE

Copyright [2018-2020] EMBL-European Bioinformatics Institute

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


package Bio::Otter::Git;

use strict;
use warnings;

#  NB: This module must not have any non-standard dependencies,
#  because the installer uses this module and it runs with a very
#  minimal $PATH, $PERL5LIB etc. (due in part to ssh-ing to
#  development hosts) so it will only find modules in default
#  locations.  If you add any dependencies here then you *must* check
#  that the installer still works.

use Try::Tiny;
use File::Basename;

### sometimes
#
# require Data::Dumper;
# require File::Path;
#
# require Cwd;
# require Otter::Paths


=head1 NAME

Bio::Otter::Git - information from version control

=head1 DESCRIPTION

Obtains and installs information from Git, so code can know where it
came from and what it needs.

From this, it has L</import> tags to

=over 4

=item * ask for the necessary server-side Ensembl version

=item * check that major version and feature branch expected by the
script are actually supplied

=back


=head1 CLASS METHODS

There are no objects here.

=cut


our $CACHE = {
# during _init, populated from Bio::Otter::Git::Cache if installed
};

our $WANT_MAJ_FEAT; # from Otter::Paths

sub _hardwired_PATH {
    # this ugly bodge is needed for the symlinked-dev corner case
    return join ':', qw( /usr/bin /bin ), # standard
      grep { -d $_ }
        qw( /usr/local/git/bin /opt/local/bin ); # for local laptops
}

sub _getcache {
    my ($pkg) = @_;
    #  Attempt to load a cache.
    return try {
        require Bio::Otter::Git::Cache;
        my $loaded = $INC{'Bio/Otter/Git/Cache.pm'};
        my $dir = $pkg->_dir;
        if (dirname(dirname($loaded)) ne $dir) {
            die "$dir loaded cache $loaded from wrong tree - suspected module shadowing";
        }
        1;
    } catch {
        if (m(\A\QCan't locate Bio/Otter/Git/Cache.pm in \E)) {
            warn "No git cache: assuming a git checkout.\n";
            0;
        }
        else {
            die "cache error: $_";
        }
    };
}

sub _try_git {
    my ($pkg) = @_;
    my $command = q(git tag);
    my $ok = $pkg->_shell_param($command);
    warn "'$command' failed: something is wrong with your git checkout"
      unless $ok;
    return $ok;
}

sub _init {
    my ($pkg) = @_;
    my $ok = $pkg->_getcache() || $pkg->_try_git();
    # Or we dev checkout and can't run Git.  ->param will return undef.
    return 0;
}

# sub new { bless ... }
# This is written with class methods and has no constructor,
# but test cases can call it on mocked out objects to feed it state.


=head2 dump()

Generates a warning identifying the code, for the benefit of logfiles.
Returns nothing.

=cut

sub dump {
    my ($pkg, $logger) = @_;
    my $feat = $pkg->param('feature');
    my $msg = sprintf "git HEAD: %s%s\n", $pkg->param('head'), $feat ? " (feature $feat)" : '';
    if ($logger) {
        $logger->info($msg);
    } else {
        warn $msg;
    }
    return;
}


=head2 as_text()

Return user friendly text describing released versions.

=cut

sub as_text {
    my ($called) = @_;
    my $head = $called->param('head');
    my $feat = $called->param('feature');
    return "v$1.$2" if !$feat && $head =~ m{^humpub-release-(\d+)-(\d+)$};
    return "$head (feature $feat)" if $feat;
    return $head;
}


=head2 taglike()

Return text describing released versions with a syntax like
otter_ipath_get's $full_version, as used by build code.

e.g. 84.04 84.51_zmq_test 85 85_slice_lock

Extended for modified releases, e.g. 84.01+7ci

=cut

sub taglike {
    my ($called) = @_;
    my $head = $called->param('head');
    my $feat = $called->param('feature');

    my $vsn;
    if ($head =~ m{^humpub-release-(\d+)-(\d+)$}) {
        $vsn = "$1.$2";
        $vsn .= "_$feat" if $feat;
    } elsif ($head =~ m{^humpub-release-(\d+)-(\d+)-(\d+)-g[a-f0-9]+$}) {
        $vsn = "$1.$2";
        my $plusci = $3;
        $vsn .= "_$feat" if $feat;
        $vsn .= "+${plusci}ci";
    } elsif ($head =~ m{^humpub-release-(\d+)-dev(?:-\d+-g[a-f0-9]+)?$}) {
        $vsn = $1;
        $vsn .= "_$feat" if $feat;
    } else {
        die "Incomprehensible head $head";
    }

    return $vsn;
}


sub _cache_template {
    my $txt = <<'CACHE_TEMPLATE';
 package Bio::Otter::Git::Cache;

 use strict;
 use warnings;

 %s

 1;

 =head1 DESCRIPTION

 This module file is auto-generated at build time by L<Bio::Otter::Git>.

 =head1 AUTHOR

 Ana Code B<email> anacode@sanger.ac.uk

 =cut
CACHE_TEMPLATE
    $txt =~ s/^ //mg; # indentation is to prevent POD being seen
    return $txt;
}


=head2 create_cache()

To be called from otterlace_build script as a oneliner, for the
side-effect of writing a .pm file.

=cut

sub create_cache {
    # Use this after support for v79 is gone.
    # otterlace_build (as of otter/79 tag) calls _create_cache
    # instead.
    my ($pkg, @arg) = @_;
    return $pkg->_create_cache(@arg);
}

sub _create_cache { # called from otterlace_build script as a oneliner
    my ($pkg, $module_dir) = @_;

    require Data::Dumper;
    my %cache = map {( $_ => $pkg->param($_) )} $pkg->_param_list;
    my $dd = Data::Dumper->new([ \%cache ], [ "${pkg}::CACHE" ]);
    my $cache_contents = $dd->Purity(1)->Useqq(1)->Sortkeys(1)->Dump;

    require File::Path;
    my $git_dir = "${module_dir}/Bio/Otter/Git";
    File::Path::make_path($git_dir);

    my $cache_path = "${git_dir}/Cache.pm";
    open my $cache_h, '>', $cache_path
        or die "failed to open the git cache '${cache_path}': $!";
    printf {$cache_h} $pkg->_cache_template(), $cache_contents
        or die "failed to print to the git cache '${cache_path}': $!";
    close $cache_h
        or die "failed to close the git cache '${cache_path}': $!";

    return;
}


=head2 param($key)

Fetch some information, either from the cache (when installed) or by
calling private methods.  Returns various strings and refs.

May error or return undef when data is not available.

=cut

sub param {
    my ($pkg, $key) = @_;
    $CACHE->{$key} = $pkg->_param($key)
        unless exists $CACHE->{$key};
    return $CACHE->{$key};
}

sub _param {
    my ($pkg, $key) = @_;
    my $command = $pkg->_param_cmd($key);
    my ($method, @arg) = @$command;
    return $pkg->$method(@arg);
}

# called via %commands
sub _shell_param {
    my ($pkg, $command) = @_;
    my $shell_command = sprintf q( cd '%s' && %s ), $pkg->_dir, $command;

    ## no critic (InputOutput::ProhibitBacktickOperators)
    my $value = try {
        qx( $shell_command );
    } catch {
        if (m(Insecure .* while running with -T switch)) {
            warn "[w] Symlinked-dev checkout under Apache?";
            $pkg->_reset_PATH;
            # then try again
            qx( $shell_command );
        } else {
            die "unexpected error with Git: $_";
        }
    };

    chomp $value;
    unless ($? == 0) {
        warn qq("$shell_command" failed);
        return;
    }
    return $value;
}

# called via %commands
sub _dist_conf { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($pkg) = @_;

    my $projdir = $pkg->_projdir;
    my $dcdir = "$projdir/dist/conf";
    opendir my $dh, $dcdir or die "opendir $dcdir: $!";

    my %dist_conf; # key = leaf, value = value
    foreach my $leaf (grep { $_ !~ /^\.\.?$/ } readdir $dh) {
        my $fn = "$dcdir/$leaf";
        open my $fh, '<', $fn or die "open $fn: $!";
        my $val = <$fh>;
        chomp $val;
#        my $comment = do { local $/; <$fh> };
#        $comment =~ s{\A\n+}{};
        $dist_conf{$leaf} = $val;
    }
    return \%dist_conf;
}

# called via %commands
sub _feature_branch { ## no critic (Subroutines::ProhibitUnusedPrivateSubroutines)
    my ($pkg) = @_;
    my $head = $pkg->_shell_param(q( git symbolic-ref -q HEAD ));
    if (!defined $head) {
        warn "See RT#387736";
        return 'DETACHED-HEAD'; # command fail warning already given
    } elsif ($head =~ m{^refs/heads/feature/(.*)$}) {
        return $1;
    } else {
        # some other branch or tag
        return '';
    }
}


=head2 dist_conf($key)

Return string from the C<dist/conf/$key> file, directly or as
recording during install.  Empty strings indicate "not set".

Dies if the key is invalid.  The set of available keys tends to grow
with major version number.

=cut

sub dist_conf {
    my ($pkg, $key) = @_;
    my $conf = $pkg->param('dist_conf');

    if (defined $key) {
        # Like team_tools' config_get function
        die "Requested dist/conf/$key is absent"
          unless exists $conf->{$key};
        return $conf->{$key};
    } else {
        my @k = sort keys %$conf;
        return @k;
    }
}


=head2 assert_match()

Check the Otter version wanted, written by L<Otter::Paths> to
C<$Bio::Otter::Git::WANT_MAJ_FEAT>, matches the actual value.

Dies if C<WANT_MAJ_FEAT> is not set or doesn't match.

=cut

sub assert_match {
    my ($pkg) = @_;
    my $got = $pkg->dist_conf('version_major');
    my $feat = $pkg->param('feature');
    $got .= "_$feat" if $feat ne '';

    die "Cannot check (major version, feature branch) match"
      unless defined $WANT_MAJ_FEAT;
    die "$pkg\->assert_match: wanted $WANT_MAJ_FEAT, got $got"
      unless $WANT_MAJ_FEAT eq $got;
    return;
}

sub _server_ensembl {
    my ($pkg) = @_;
    my $evsn = $pkg->dist_conf('server_ensembl_version');
    return "ensembl$evsn";
}


=head2 import(...)

The following tags may be provided, to ask L<Otter::Paths> to find the
appropriate library on C<@INC>.

=over 4

=item :server_ensembl

Provide the necessary server ensembl API, using L</dist_conf>.

=item :match

Calls L</assert_match> for the side effect of C<die>ing when the
(major version, feature branch) expected by L<Otter::Path> do not
match our actual version.

This is mediated by C<$Bio::Otter::Git::WANT_MAJ_FEAT>.

=back

=cut

sub import {
    my ($pkg, @key) = @_;
    return unless @key;

    my @import;
    foreach my $key (@key) {
        if ($key eq ':server_ensembl') {
            push @import, $pkg->_server_ensembl;
        } elsif ($key eq ':match') {
            $pkg->assert_match;
        } else {
            die "Unknown import key '$key'";
        }
    }
    if (@import) {
        require Otter::Paths;
        Otter::Paths->import(@import);
    }
    return;
}


{
    my %commands =
      (head => [ _shell_param => q(git describe --tags --match 'humpub-release-*' HEAD) ],
       dist_conf => [ '_dist_conf' ],
       feature => [ '_feature_branch' ],
      );

    sub _param_list {
        return keys %commands;
    }

    sub _param_cmd {
        my ($pkg, $key) = @_;
        my $command = $commands{$key};
        die qq(invalid git parameter key "${key}") unless $command;
        return $command;
    }
}

{
    my $dir = dirname __FILE__;
    sub _dir { return $dir }
}

sub _projdir {
    my ($pkg) = @_;
    my $dir = $pkg->_dir; # of this module file
    my $tail = __PACKAGE__;
    $tail =~ s{::[^:]+$}{};
    $tail =~ s{::}{/};
    my $pat = qr{(^|/)(lib|modules)/\Q$tail\E$};
    # $2 alternation in case of a rename to more Perl-ish layout

    if ($dir =~ s{$pat}{}) {
        # a plain checkout.
        return $dir;
    } # else probably symlinked from a webvm.git checkout

    require Cwd;
    $dir = Cwd::abs_path($dir);
    if ($dir =~ s{$pat}{}) {
        # fixed by resolving symlink
        return $dir;
    }
    die "Cannot make projdir from $dir with tail $tail";
}

sub _reset_PATH {
    my ($pkg) = @_;
    my $new_path = $pkg->_hardwired_PATH;
    warn "Resetting \$ENV{PATH}\n  old PATH=$ENV{PATH}\n  new PATH=$new_path\n"
      unless $ENV{PATH} eq $new_path;
    $ENV{PATH} = $new_path;
    return;
}

__PACKAGE__->_init;

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

