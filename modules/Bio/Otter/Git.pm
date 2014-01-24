
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


our $CACHE = {
# during _init, populated from Bio::Otter::Git::Cache if installed
};

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
    return try {
        my $command = q(git tag);
        my $dir = $pkg->_dir;
        my $ok = system(qq(cd '$dir' && $command > /dev/null)) == 0;
        warn "'$command' failed: something is wrong with your git checkout"
          unless $ok;
        $ok;
    } catch {
        if (m(Insecure .* while running with -T switch)) {
            warn "Dev checkout under Apache? Cannot run git: $_";
            0;
        } else {
            die "unexpected error with Git: $_";
        }
    };
}

sub _init {
    my ($pkg) = @_;
    my $ok = $pkg->_getcache() || $pkg->_try_git();
    # Or we dev checkout and can't run Git.  ->param will return undef.
    return 0;
}


sub dump { # for the benefit of logfiles
    my ($pkg) = @_;
    my $feat = $pkg->param('feature');
    warn sprintf "git HEAD: %s%s\n", $pkg->param('head'),
      $feat ? " (feature $feat)" : '';
    return;
}

# Show something more user friendly for released versions
sub as_text {
    my ($called) = @_;
    my $head = $called->param('head');
    my $feat = $called->param('feature');
    return "v$1.$2" if !$feat && $head =~ m{^humpub-release-(\d+)-(\d+)$};
    return "$head (feature $feat)" if $feat;
    return $head;
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

sub create_cache { # to be called from otterlace_build script as a oneliner
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

# may error or return undef when data is not available
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
    my $value = qx( $shell_command ); ## no critic (InputOutput::ProhibitBacktickOperators)
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
        return 'DETACHED-HEAD'; # command fail warning already given
    } elsif ($head =~ m{^refs/heads/feature/(.*)$}) {
        return $1;
    } else {
        # some other branch or tag
        return '';
    }
}

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
    $dir =~ s{(^|/)(lib|modules)/\Q$tail\E$}{}
      or die "Cannot make projdir from $dir with tail $tail";
    return $dir;
}

__PACKAGE__->_init;

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

