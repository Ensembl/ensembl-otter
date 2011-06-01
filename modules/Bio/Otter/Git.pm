
package Bio::Otter::Git;

use strict;
use warnings;

use File::Basename;

my $dir = dirname __FILE__;

my $commands = {
    head => q(git describe --tags HEAD),
};

my $param = {
    # @PARAMETERS@
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

