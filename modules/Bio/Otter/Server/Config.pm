package Bio::Otter::Server::Config;
use strict;
use warnings;

use Bio::Otter::SpeciesDat;
use Bio::Otter::Version;

=head1 NAME

Bio::Otter::Server::Config - obtain config data for Otter Server

=head1 DESCRIPTION

This module contains only class methods.

=cut


sub data_dir {
    my ($pkg) = @_;

    my $root = $ENV{'DOCUMENT_ROOT'};
    # Trim off the trailing /dir (usually htdocs)
    $root =~ s{/[^/]+$}{}
      or die "Unexpected DOCUMENT_ROOT format '$ENV{DOCUMENT_ROOT}'";
    return join('/', $root, 'data', 'otter');
}


sub SpeciesDat {
    my ($pkg) = @_;
    my $fn = $pkg->data_dir . '/species.dat';
    return Bio::Otter::SpeciesDat->new($fn);
}


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
