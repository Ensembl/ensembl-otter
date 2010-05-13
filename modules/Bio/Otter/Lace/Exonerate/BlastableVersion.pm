
## no critic(Modules::RequireFilenameMatchesPackage)

package BlastableVersion;

use strict;
use warnings;

#### Stop anyone else loading their own BlastableVersion
$INC{q(BlastableVersion.pm)}++;

use vars qw(%versions $debug $revision);

$debug = 0;
$revision='$Revision: 1.5 $ ';
$revision =~ s/\$.evision: (\S+).*/$1/;

#### CONSTRUCTORS

sub new {
    my $proto = shift;
    my $self = { };
    bless ($self, ref($proto) || $proto);
    return $self;
}

#### ACCESSOR METHODS

sub date {
    return localtime;
}

sub name {
    return $0;
}

sub version {
    return 1.0.0;
}

sub sanger_version {
    return 1.0.0;
}

#### PUBLIC METHODS

sub force_dbi { }
sub set_hostname { }
sub get_version { }

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


