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

    die "data_dir $data (near root '$root' from $src): not found"
      unless -d $data;

    return $data;
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
