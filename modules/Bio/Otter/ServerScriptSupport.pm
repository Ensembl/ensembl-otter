
use strict;

package Bio::EnsEMBL::DBSQL::StatementHandle;

# Work around DBI/DBD::mysql bug on webservers
sub bind_param {
    my ($self, $pos, $value, $attr) = @_;

    # Make $attr a hash ref if it is not
    if (defined $attr) {
        unless (ref $attr) {
            $attr = {TYPE => $attr};
        }
        $self->SUPER::bind_param($pos, $value, $attr);
    } else {
        $self->SUPER::bind_param($pos, $value);
    }
}

package Bio::Otter::ServerScriptSupport;

use strict;

use Bio::Otter::Author;
use Bio::Vega::Author;
use Bio::Otter::Version;
use Bio::Otter::Lace::TempFile;

use SangerWeb;

use base ('CGI', 'Bio::Otter::MFetcher');
#use CGI::Carp 'fatalsToBrowser';

CGI->nph(1);

BEGIN {
    warn "otter_srv script start: $0\n";
}
END {
    warn "otter_srv script end: $0\n";
}

sub new {
    my $pkg = shift;
    
    my $self = $pkg->SUPER::new(@_);
    if ($self->local_user) {
        $self->authenticate_user;
    } else {
        $self->authorized_user
    }

    # '/GPFS/data1/WWW/SANGER_docs/data/otter/48/species.dat';
    $self->species_dat_filename( join('/',
                $self->server_root,
                'data',
                'otter',
                $self->otter_version,
                'species.dat')
    );

    return $self;
}

sub dataset_name { # overloads the one provided by MFetch
    my( $self ) = @_;
    
    my $dataset_name;
    unless ($dataset_name = $self->{'_dataset_name'}) {
        $self->{'_dataset_name'} = $dataset_name = $self->require_argument('dataset');
    }
    return $dataset_name;
}


############## getters: ###########################

sub csn {   # needed by logging mechanism
    my $self = shift @_;

    my $csn;
    unless ($csn = $self->{'_current_script_name'}) {
        ($csn) = $ENV{'SCRIPT_NAME'} =~ m{([^/]+)$};
        die "Can't parse script name from '$ENV{SCRIPT_NAME}'"
          unless $csn;
        $self->{'_current_script_name'} = $csn;
    }
    return $csn
}

sub otter_version {
    my ($self) = @_;
    
    my $ver;
    unless ($ver = $self->{'_otter_version'}) {
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

    # overloading because certain species may need to be masked
sub load_species_dat_file {
    my ($self) = @_;

    $self->SUPER::load_species_dat_file(@_);

    unless ($self->local_user || $self->internal_user) {
        
            # External users only see datasets listed after their names in users.txt file
        my $user = $self->authorized_user;
        my $allowed = $self->users_hash->{$user};

        $self->keep_only_datasets($allowed);
    }
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
    if (open my $list, $usr_file) {
        while (<$list>) {
            s/#.*//;            # Remove comments
            s/(^\s+|\s+$)//g;   # Remove leading or trailing spaces
            next if /^$/;       # Skip lines which are now blank
            my ($user_name, @allowed_datasets) = split;
            foreach my $ds (@allowed_datasets) {
                $usr_hash->{$user_name}{$ds} = 1;
            }
        }
        close $list or die "Error reading '$list'; $!";
    }
    return $usr_hash;
}

sub authenticate_user {
    my ($self) = @_;
    
    my $sw = SangerWeb->new({ cgi => $self });
    
    if (my $user = $sw->username) {
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

sub admin_user {
    my ($self) = @_;
    
    my $user = $self->authorized_user;
    return $self->internal_user && $self->users_hash->{$user}{'admin'};
}

sub local_user {
    return $ENV{'localuser'} =~ /local/ ? 1 : 0;
}

############## I/O: ################################

sub log {
    my ($self, $line) = @_;

    return unless $self->param('log');

    print STDERR '['.$self->csn()."] $line\n";
}
    
sub send_response{
    my ($self, $response, $wrap) = @_;

    print $self->header(
        -status => 200,
        -type   => 'text/plain',
        );

    if ($wrap) {
        print $self->wrap_response($response);
    } else {
        print $response;
    }
}

sub wrap_response {
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
      $self->wrap_response(" <response>\n    ERROR: $reason\n </response>\n");
    $self->log("ERROR: $reason\n");

    exit(1);
}

sub require_argument {
    my ($self, $argname) = @_;

    my $value = $self->param($argname);
    
    if (defined $value) {
        return $value;
    } else {
        $self->error_exit("No '$argname' argument defined");
    }
}

sub return_emptyhanded {
    my $self = shift @_;

    $self->send_response('', 1);
    exit(0); # <--- this forces all the scripts to exit normally
}

sub tempfile_from_argument {
    my $self      = shift @_;
    my $argname   = shift @_;

    my $file_name = shift @_ || $self->csn().'_'.$self->require_argument('author').'.xml';

    my $tmp_file = Bio::Otter::Lace::TempFile->new;
    $tmp_file->root('/tmp');
    $tmp_file->name($file_name);
    my $full_name = $tmp_file->full_name();

    $self->log("Dumping the data to the temporary file '$full_name'");

    my $write_fh = eval{
        $tmp_file->write_file_handle();
    } || $self->error_exit("Can't write to '$full_name' : $!");
    print $write_fh $self->require_argument($argname);

    return $tmp_file;
}

############# Creation of an Author object from arguments #######

sub make_Author_obj {
    my ($self, $author_name) = @_;

    $author_name ||= $self->authorized_user;
    
    #my $author_email = $self->require_argument('email');
    my $class        = $self->running_headcode() ? 'Bio::Vega::Author' : 'Bio::Otter::Author';

    return $class->new(-name => $author_name, -email => $author_name);
}

sub fetch_Author_obj {
    my ($self, $author_name) = @_;

    $author_name ||= $self->authorized_user;

    if($self->running_headcode() != $self->dataset_headcode()) {
        $self->error_exit("RunningHeadcode != DatasetHeadcode, cannot fetch Author");
    }

    my $author_adaptor = $self->otter_dba()->get_AuthorAdaptor();

    my $author_obj;
    eval{
        $author_obj = $author_adaptor->fetch_by_name($author_name);
    };
    if($@){
        $self->error_exit("Failed to get an author.\n$@") unless $author_obj;
    }
    return $author_obj;
}

1;

