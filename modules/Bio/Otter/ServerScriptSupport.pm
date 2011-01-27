
package Bio::Otter::ServerScriptSupport;

use strict;
use warnings;

use Bio::Vega::Author;
use Bio::Otter::Version qw( $SCHEMA_VERSION $XML_VERSION );
use Bio::Otter::Lace::TempFile;
use Bio::Otter::Lace::ViaText qw( %LangDesc &GenerateFeatures );
use Bio::Vega::DBSQL::SimpleBindingAdaptor;
use Bio::Vega::Utils::GFF;
use Bio::Vega::Enrich::SliceGetAllAlignFeatures;

use IO::Compress::Gzip qw(gzip);

use SangerWeb;

use base ('CGI', 'Bio::Otter::MFetcher');


BEGIN {
    warn "otter_srv script start: $0\n";
}
END {
    warn "otter_srv script end: $0\n";
}

our $COMPRESSION_ENABLED;
$COMPRESSION_ENABLED = 1 unless defined $COMPRESSION_ENABLED;

sub new {
    my ( $pkg, %params ) = @_;

    my $self = $pkg->CGI::new();    # CGI part of the object needs initialization

    @{$self}{ keys %params } = values %params; # set the rest of the parameters

    if ($self->show_restricted_datasets || ! $self->local_user) {
        $self->authorized_user;
    } else {
        $self->authenticate_user;
    }

    # '/GPFS/data1/WWW/SANGER_docs/data/otter/48/species.dat';
    $self->species_dat_filename($self->data_dir . '/species.dat');

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
    my ($self) = @_;

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
    my $self = shift;

    $self->SUPER::load_species_dat_file(@_);

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
configured with us as the CGI instance.

It is important to instantiate only one CGI (or subclass) instance,
because it will eat the POST input.

=cut

sub sangerweb {
    my ($self) = @_;

    return $self->{'_sangerweb'} ||= SangerWeb->new({ cgi => $self });
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

sub log { ## no critic(Subroutines::ProhibitBuiltinHomonyms)
    my ($self, $line) = @_;

    return unless $self->param('log');

    print STDERR '['.$self->csn()."] $line\n";

    return;
}

sub send_response {

    my ($self, $response, $wrap, $compress) = @_;

    if ($COMPRESSION_ENABLED && $compress) {
        print $self->header(
            -status             => 200,
            -type               => 'text/plain',
            -content_encoding   => 'gzip',
        );

        my $gzipped;
        gzip \$response => \$gzipped;
        print $gzipped;
    }
    else {
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

    return;
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

    $self->error_exit("No '$argname' argument defined")
        unless defined $value;

    return $value;
}

sub return_emptyhanded {
    my ($self) = @_;

    $self->send_response('', 1);
    exit(0); # <--- this forces all the scripts to exit normally
}

sub tempfile_from_argument {
    my ($self, $argname, $file_name) = @_;

    $file_name ||= $self->csn().'_'.$self->require_argument('author').'.xml';

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

    return Bio::Vega::Author->new(-name => $author_name, -email => $author_name);
}

sub fetch_Author_obj {
    my ($self, $author_name) = @_;

    $author_name ||= $self->authorized_user;

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

sub get_requested_features {

    my $self = shift;

    my @feature_kinds  = split(/,/, $self->require_argument('kind'));
    my $analysis_list = $self->param('analysis');
    my @analysis_names = $analysis_list ? split(/,/, $analysis_list) : ( undef );
    my $filter_module = $self->param('filter_module');

    my @feature_list = ();

    foreach my $analysis_name (@analysis_names) {
        foreach my $feature_kind (@feature_kinds) {
            my $param_descs = $LangDesc{$feature_kind}{-call_args};
            my $getter_method = "get_all_${feature_kind}s";

            my @param_list = ();
            foreach my $param_desc (@$param_descs) {
                my ($param_name, $param_def_value, $param_separator) = @$param_desc;

                my $param_value = (scalar(@$param_desc)==1)
                    ? $self->require_argument($param_name)
                    : defined($self->param($param_name))
                    ? $self->param($param_name)
                    : $param_def_value;
                if($param_value && $param_separator) {
                    $param_value = [split(/$param_separator/,$param_value)];
                }
                $param_value = $analysis_name if $param_value =~ /$analysis_name/;
                push @param_list, $param_value;
            }

            my $features = $self->fetch_mapped_features($feature_kind, $getter_method, \@param_list,
                                                        map { defined($self->param($_)) ? $self->param($_) : '' }
                                                        qw(cs name type start end metakey csver csver_remote)
                );

            push @feature_list, @$features;
        }
    }

    if ($filter_module) {
        
        # detaint the module string
        
        my ($module_name) = $filter_module =~ /^((\w+::)*\w+)$/;

        # for the moment be very conservative in what we allow

        if ($module_name =~ /^Bio::Vega::ServerAnalysis::\w+$/) {
      
            eval "require $module_name"; ## no critic(BuiltinFunctions::ProhibitStringyEval)
            
            die "Failed to 'require' module $module_name: $@" if $@;
            
            my $filter = $module_name->new;
            
            $self->log(scalar(@feature_list)." features before filtering...");
            
            @feature_list = $filter->run(\@feature_list);
        
            $self->log(scalar(@feature_list)." features after filtering...");
        }
        else {
            die "Invalid filter module: $filter_module";
        }
    }

    # workaround: some of our pipelines put features on the wrong strand
    if ( $self->param('swap_strands') ) {
        for my $f (@feature_list) {
            if ($f->can('hstrand') && $f->hstrand == -1) {
                $f->hstrand($f->hstrand * -1);
                $f->strand($f->strand * -1);
                $f->cigar_string(join '', reverse($f->cigar_string =~ /(\d*[A-Za-z])/g))
            }
        }
    }

    return \@feature_list;
}

sub empty_gff_header {
    
    my $self = shift;
    
    my $name    = $self->param('type');
    my $start   = $self->param('start');
    my $end     = $self->param('end');
    
    if ($self->param('rebase')) {
        $name .= '_'.$start.'-'.$end;
        $end = $end - $start + 1;
        $start = 1;
    }
    
    return Bio::Vega::Utils::GFF::gff_header($name, $start, $end);
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

