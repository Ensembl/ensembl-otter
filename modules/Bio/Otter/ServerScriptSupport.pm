
package Bio::Otter::ServerScriptSupport;

use strict;
use warnings;

use Bio::Vega::Author;
use Bio::Otter::Version qw( $SCHEMA_VERSION $XML_VERSION );

use IO::Compress::Gzip qw(gzip);

use CGI;
use SangerWeb;

use base ('Bio::Otter::MFetcher');


BEGIN {
    warn "otter_srv script start: $0\n";
}
END {
    warn "otter_srv script end: $0\n";
}

our $COMPRESSION_ENABLED;
$COMPRESSION_ENABLED = 1 unless defined $COMPRESSION_ENABLED;

my $LOG;

sub new {
    my ( $pkg, @args ) = @_;

    my $self = {
        -cgi          => CGI->new,
        -compression  => 0,
        -content_type => 'text/plain',
        @args,
    };
    bless $self, $pkg;

    if ($self->show_restricted_datasets || ! $self->local_user) {
        $self->authorized_user;
    } else {
        $self->authenticate_user;
    }

    $self->dataset_name($self->param('dataset'));
    $self->species_dat_filename($self->data_dir . '/species.dat');

    $LOG = $self->param('log');

    return $self;
}

sub cgi {
    my ($self) = @_;
    return $self->{-cgi};
}

sub header {
    my ($self, @args) = @_;
    return $self->cgi->header(@args);
}

sub param {
    my ($self, @args) = @_;
    return $self->cgi->param(@args);
}


############## getters: ###########################

sub otter_version {
    my ($self) = @_;

    my $ver;
    unless($ver = $self->{'_otter_version'}) {
        ($ver) = $ENV{'SCRIPT_NAME'} =~ m{/otter/(\d+)/};
        die "Unexpected script location '$ENV{SCRIPT_NAME}'"
          unless $ver;
        $self->{'_otter_version'} = $ver;
    }
    return $ver;
}

sub server_root {
    my ($self) = @_;

    my $root;
    unless ($root = $self->{'server_root'}) {
        $root = $ENV{'DOCUMENT_ROOT'};
        # Trim off the trailing /dir
        $root =~ s{/[^/]+$}{}
          or die "Unexpected DOCUMENT_ROOT format '$ENV{DOCUMENT_ROOT}'";
        $self->{'server_root'} = $root;
    }
    return $root;
}

sub data_dir {
    my ($self) = @_;

    my $data_dir;
    unless ($data_dir = $self->{'data_dir'}) {
        $data_dir = join('/', $self->server_root, 'data', 'otter', $self->otter_version);
    }
    return $data_dir;
}

    # overloading because certain species may need to be masked
sub load_species_dat_file {
    my ($self, @args) = @_;

    $self->SUPER::load_species_dat_file(@args);

    unless ($self->local_user || $self->internal_user) {        
        # External users only see datasets listed after their names in users.txt file
        $self->keep_only_datasets($self->allowed_datasets);
    }
    my $datasets_to_keep = $self->show_restricted_datasets ? $self->allowed_datasets : {};
    $self->remove_restricted_datasets($datasets_to_keep);

    return;
}

sub allowed_datasets {
    my ($self) = @_;

    my $user = $self->authorized_user;
    return $self->users_hash->{$user} || {};
}

sub users_hash {
    my ($self) = @_;

    my $usr;
    unless ($usr = $self->{'_users_hash'}) {
        my $usr_file = join('/', $self->server_root, 'data', 'otter', $self->otter_version, 'users.txt');
        $usr = $self->{'_users_hash'} = $self->read_user_file($usr_file);
    }
    return $usr;
}

sub read_user_file {
    my ($self, $usr_file) = @_;

    my $usr_hash = {};
    if (open my $list, '<', $usr_file) {
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
        close $list or die "Error reading '$list'; $!";
    }
    return $usr_hash;
}


=head2 sangerweb()

Instance method.  Cache and return an instance of L<SangerWeb>
configured with our CGI instance.

=cut

sub sangerweb {
    my ($self) = @_;

    return $self->{'_sangerweb'} ||=
        SangerWeb->new({ cgi => $self->cgi });
}


sub authenticate_user {
    my ($self) = @_;

    my $sw = $self->sangerweb;

    if (my $user = lc($sw->username)) {
        my $auth_flag     = 0;
        my $internal_flag = 0;

        if ($user =~ /^[a-z0-9]+$/) {   # Internal users (simple user name)
            $auth_flag = 1;
            $internal_flag = 1;
        } elsif($self->users_hash->{$user}) {  # Check external users (email address)
            $auth_flag = 1;
        }

        if ($auth_flag) {
            $self->{'_authorized_user'} = $user;
            $self->{'_internal_user'}   = $internal_flag;
        }
    }

    return;
}

sub authorized_user {
    my ($self) = @_;

    my $user;
    unless ($user = $self->{'_authorized_user'}) {
        $self->authenticate_user;
        $self->unauth_exit('User not authorized')
            unless $self->{'_authorized_user'};
    }
    return $user;
}

sub internal_user {
    my ($self) = @_;

    # authorized_user sets '_internal_user', and is called
    # by new(), so this hash key will be populated.
    return $self->{'_internal_user'};
}


=head2 local_user()

Is the caller on the WTSI internal network?

=cut

sub local_user {

    return $ENV{'HTTP_CLIENTREALM'} =~ /sanger/ ? 1 : 0;
}

sub show_restricted_datasets {
    my ($self) = @_;

    if (my $client = $self->param('client')) {
        return $client =~ /otterlace/;
    } else {
        return;
    }
}

############## I/O: ################################

my $csn;
($csn) = $ENV{'SCRIPT_NAME'} =~ m{([^/]+)$} if defined $ENV{'SCRIPT_NAME'};
$SIG{__WARN__} = sub { ## no critic (Variables::RequireLocalizedPunctuationVars)
    my ($line) = @_;
    return unless $LOG;
    $line = sprintf "[%s] %s", $csn, $line if defined $csn;
    warn $line;
    return;
};

sub send_file {
    my ($pkg, $name, @args) = @_;

    $pkg->send_response(
        @args, # passed to the constructor
        sub {
            my ($self) = @_;

            my $path = sprintf "%s/%s", $self->data_dir, $name;
            open my $fh, '<', $path or die "Can't read '$path' : $!";
            local $/ = undef;
            my $content = <$fh>;
            close $fh;

            return $content;
        });

    return;
}

sub send_response {
    my ($self, @args) = @_;

    my $sub = pop @args;
    my $server = $self->new(@args);
    my $response;
    if (eval { $response = $sub->($server); 1; }) {
        $server->_send_response($response);
    }
    else {
        $server->error_exit($@);
    }

    return;
}

sub _send_response {

    my ($self, $response) = @_;

    my $content_type = $self->{-content_type};

    if ($COMPRESSION_ENABLED && $self->{-compression}) {
        print $self->header(
            -status             => 200,
            -type               => $content_type,
            -content_encoding   => 'gzip',
        );

        my $gzipped;
        gzip \$response => \$gzipped;
        print $gzipped;
    }
    else {
        print
            $self->header(
                -status => 200,
                -type   => $content_type,
            ),
            $response,
            ;
    }

    return;
}

sub otter_wrap_response {
    my ($self, $response) = @_;

    return qq{<?xml version="1.0" encoding="UTF-8"?>\n}
      . qq{<otter schemaVersion="$SCHEMA_VERSION" xmlVersion="$XML_VERSION">\n}
      . $response
      . qq{</otter>\n};
}

sub unauth_exit {
    my ($self, $reason) = @_;

    print $self->header(
        -status => 403,
        -type   => 'text/plain',
        ), $reason;
    exit(1);
}

sub error_exit {
    my ($self, $reason) = @_;

    chomp($reason);

    print $self->header(
        -status => 417,
        -type   => 'text/plain',
        ),
      $self->otter_wrap_response(" <response>\n    ERROR: $reason\n </response>\n");
    warn "ERROR: $reason\n";

    exit(1);
}

sub require_argument {
    my ($self, $argname) = @_;

    my $value = $self->param($argname);

    die "No '$argname' argument defined"
        unless defined $value;

    return $value;
}

############# Creation of an Author object #######

sub make_Author_obj {
    my ($self) = @_;

    my $author_name = $self->authorized_user;
    #my $author_email = $self->require_argument('email');

    return Bio::Vega::Author->new(
        -name  => $author_name,
        -email => $author_name,
        );
}


############## the requested region: ###########################

sub get_requested_slice {
    my ($self) = @_;

    my $cs      = $self->param('cs')     || 'chromosome';
    my $csver   = $self->param('csver')  || (($cs eq 'chromosome') ? 'Otter' : undef);
    my $name    = $self->require_argument('name');
    my $type    = $self->require_argument('type');
    my $start   = $self->require_argument('start');
    my $end     = $self->require_argument('end');
    my $strand  = $self->param('strand') || undef;

    warn "Getting slice... [$name | $type] [$start] [$end]\n";

    my $odba  = $self->otter_dba;
    my $slice = $self->get_slice($odba, $cs, $name, $type, $start, $end, $strand, $csver);

    return $slice;
}


## no critic(Modules::ProhibitMultiplePackages)

package Bio::EnsEMBL::DBSQL::StatementHandle;

use strict;
use warnings;

# Work around DBI/DBD::mysql bug on webservers
sub bind_param {
    my ($self, $pos, $value, $attr) = @_;

    # Make $attr a hash ref if it is not
    if (defined $attr) {
        unless (ref $attr) {
            $attr = {TYPE => $attr};
        }
        return $self->SUPER::bind_param($pos, $value, $attr);
    } else {
        return $self->SUPER::bind_param($pos, $value);
    }
}

1;

__END__

=head1 AUTHOR

Leo Gordon B<email> lg4@sanger.ac.uk

