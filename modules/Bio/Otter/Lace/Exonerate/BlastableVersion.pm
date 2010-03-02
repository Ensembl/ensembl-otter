
## no critic(Modules::RequireFilenameMatchesPackage)

package BlastableVersion;

use strict;
use warnings;

#### Stop anyone else loading their own BlastableVersion
$INC{q(BlastableVersion.pm)}++;

#### Configurable variables

my $cache_file = '/var/tmp/blast_versions';
my $tracking_db = 'mysql:blastdb;cbi2.internal.sanger.ac.uk';
my $tracking_user = 'blastdbro';
my $tracking_pass = '';

#### No more configurable variables

use vars qw(%versions $debug $revision);

$debug = 0;
$revision='$Revision: 1.3 $ ';
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
