package Bio::Otter::Server::Config;
use strict;
use warnings;

use Bio::Otter::SpeciesDat;
use Bio::Otter::Version;

=head1 NAME

Bio::Otter::Server::Config - obtain config data for Otter Server

=head1 DESCRIPTION

This module contains only class methods.

=head1 CLASS METHODS

=head2 data_dir()

Return the Otter Server config directory.

=cut


sub data_dir {
    my ($pkg) = @_;

    my ($root, $src) = ($ENV{'DOCUMENT_ROOT'}, '%ENV');

    if (!defined $root) {
        # For internal non-web machines, provide the central copy to
        # remove the need to pretend we have DOCUMENT_ROOT .

        ($root, $src) = ('/nfs/WWWdev/SANGER_docs/htdocs', 'fallback')
          if -d '/software/anacode';
        # Web machines shouldn't have a fallback, too magical.
    }

    die "Cannot find data_dir via DOCUMENT_ROOT or fallback" # need another way?
      unless defined $root;

    # Trim off the trailing /dir (usually htdocs)
    my $data = $root;
    $data =~ s{/[^/]+$}{}
      or die "Unexpected DOCUMENT_ROOT format '$root' from $src";
    $data = join('/', $data, 'data', 'otter');

    # Possible override for testing config
    if (defined(my $dev_cfg = $pkg->_dev_config)) {
        ($data, $src) = ($dev_cfg, 'mua_dev');
    }

    die "data_dir $data (near root '$root' from $src): not found"
      unless -d $data;

    return $data;
}


=head mid_url_args()

Return a hashref of key-value items taken from C<$1> of URL
C<http://server:port/cgi-bin/otter([^/]*)/\d+/\w+>

This is empty in normal production use, and will be empty if the
pattern doesn't match (no errors raised).

In DEVEL mode servers it may be used to point L</data_dir> elsewhere.
CGI escapes are %-decoded and the result is re-tainted.

=cut

sub mid_url_args {
    my ($pkg) = @_;
    my %out;
    my $retaint = substr("$0$^X",0,0); # CGI.pm 3.49 does this too

    if ($ENV{REQUEST_URI} =~ m{^/cgi-bin/otter([^/]*)/\d+/}) {
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
    my $developer = $pkg->mid_url_args->{'~'};
    return () unless defined $developer;

    my $dev_home = (getpwnam($developer))[7];
    die "Developer config for $developer: unknown user" unless defined $dev_home;
    my ($gname, $gmemb) = (getgrgid( $( ))[0, 3];
    my @ok_user = split / /, $gmemb;
    die "Developer config for $developer: not a member of group $gname"
      unless grep { $developer eq $_ } @ok_user;

    return "$dev_home/.otter/server-config";
}


=head2 SpeciesDat()

Return a fresh instance of L<Bio::Otter::SpeciesDat> from the Otter
Server config directory.

=cut

sub SpeciesDat {
    my ($pkg) = @_;
    my $fn = $pkg->data_dir . '/species.dat';
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
    my $fn = $pkg->data_dir . '/designations.txt';
    return $pkg->_desig($fn);
}

sub _desig {
    my ($pkg, $fn) = @_;
    my %desig;
    open my $fh, '<', $fn
      or die "Error reading version designations $fn: $!";
    while (<$fh>) {
        next if /^\s+$|^#/;
        if (m{^(\S+)\s+(\d+(?:\.\d+)?)$}) {
            $desig{$1} = $2;
        } else {
            warn "Skipped bad version designation $_"
        }
    }
    close $fh;
    return \%desig;
}



=head2 users_hash()

Return a freshly loaded hash C<< ->{$user}{$dataset} = 1 >> from the
Otter Server config directory.

=cut

sub users_hash {
    my ($pkg) = @_;
    my $usr_file = $pkg->data_dir . '/users.txt';
    return $pkg->_read_user_file($usr_file);
}

sub _read_user_file {
    my ($pkg, $usr_file) = @_;

    my $usr_hash = {};

    open my $list, '<', $usr_file
        or die "Error opening '$usr_file'; $!";
    while (<$list>) {
        s/#.*//;            # Remove comments
        s/(^\s+|\s+$)//g;   # Remove leading or trailing spaces
        next if /^$/;       # Skip lines which are now blank
        my ($user_name, @allowed_datasets) = split;
        $user_name = lc($user_name);
        foreach my $ds (@allowed_datasets) {
            $usr_hash->{$user_name}{$ds} = 1;
        }
    }
    close $list or die "Error closing '$usr_file'; $!";

    return $usr_hash;
}



=head2 get_file($name)

Return the contents of the Otter Server config file C<$name> for the
current major version.

=cut

sub get_file {
    my ($pkg, $name) = @_;

    my $path = sprintf "%s/%s/%s"
        , $pkg->data_dir, Bio::Otter::Version->version, $name;
    open my $fh, '<', $path or die "Can't read '$path' : $!";
    local $/ = undef;
    my $content = <$fh>;
    close $fh;

    return $content;
}


=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

1;
