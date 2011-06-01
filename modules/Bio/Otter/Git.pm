
package Bio::Otter::Git;

use strict;
use warnings;

#  NB: This module must not have any non-standard dependencies,
#  because the installer uses this module and it runs with a very
#  minimal $PATH, $PERL5LIB etc. (due in part to ssh-ing to
#  development hosts) so it will only find modules in default
#  locations.  If you add any dependencies here then you *must* check
#  that the installer still works.
 
use File::Basename;

my $dir = dirname __FILE__;

my $commands = {
    head => q(git describe --tags HEAD),
};

#  We cache the output of the commands in $param.  The installer will
#  update the cache in-place so that the installed Otterlace will use
#  the cached git state and not attempt to rerun any git commands.
#  This is necessary because the installed Otterlace is not in a git
#  repository so running git would fail.

my $param = {
    # @PARAMETERS@ - DO NOT REMOVE THIS PLACEHOLDER!!! - the installer needs it
};

sub dump { ## no critic (Subroutines::ProhibitBuiltinHomonyms)
    my ($pkg) = @_;
    warn sprintf "git HEAD: %s\n", $pkg->param('head');
    return;
}

sub dump_as_perl {
    my ($pkg) = @_;
    printf "    %s => q(%s),\n", $_, $pkg->param($_)
        for keys %{$commands};
    return;
}

sub param {
    my ($pkg, $key) = @_;
    $param->{$key} = $pkg->_param($key)
        unless exists $param->{$key};
    return $param->{$key};
}

sub _param {
    my ($pkg, $key) = @_;
    my $command = $commands->{$key};
    die qq(invalid git parameter key "${key}") unless $command;
    my $shell_command = sprintf q( cd '%s' && %s ), $dir, $command;
    my $value = qx( $shell_command ); ## no critic(InputOutput::ProhibitBacktickOperators)
    chomp $value;
    unless ($? == 0) {
        warn qq("$shell_command" failed);
        return;
    }
    return $value;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

