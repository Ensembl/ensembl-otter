
### Bio::Otter::Lace::Client

package Bio::Otter::Lace::Client;

use strict;
use Carp qw{ confess cluck };
use Sys::Hostname qw{ hostname };
use LWP;
use Bio::Otter::LogFile;
use Bio::Otter::Lace::DataSet;
use Bio::Otter::Lace::AceDatabase;
use Bio::Otter::Lace::PersistentFile;
use Bio::Otter::Lace::DasClient;
use Bio::Otter::Transform::DataSets;
use Bio::Otter::Transform::SequenceSets;
use Bio::Otter::Converter;
use Bio::Otter::Lace::TempFile;
use URI::Escape qw{ uri_escape };
use MIME::Base64;
use Hum::EnsCmdLineDB;

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub host {
    my( $self, $host ) = @_;

    warn "Set using the Config file please.\n" if $host;

    return $self->option_from_array([qw( client host )]);
}

sub port {
    my( $self, $port ) = @_;
    
    warn "Set using the Config file please.\n" if $port;

    return $self->option_from_array([qw( client port )]);
}

sub write_access {
    my( $self, $write_access ) = @_;
    
    warn "Set using the Config file please.\n" if $write_access;

    return $self->option_from_array([qw( client write_access )]) || 0;
}

sub author {
    my( $self, $author ) = @_;
    
    warn "Set using the Config file please.\n" if $author;

    return $self->option_from_array([qw( client author )]) || (getpwuid($<))[0];
}

sub email {
    my( $self, $email ) = @_;
    
    warn "Set using the Config file please.\n" if $email;

    return $self->option_from_array([qw( client email )]) || (getpwuid($<))[0];
}
sub debug{
    my ($self, $debug) = @_;

    warn "Set using the Config file please.\n" if $debug;

    return $self->option_from_array([qw( client debug )]) ? 1 : 0;
}

sub make_log_file {
    my( $self, $file_root ) = @_;
    
    $file_root ||= 'client';
    
    my $log_dir = $self->option_from_array([qw( client logdir )])
        or return;
    
    # Make $log_dir into absolute file path
    # It is assumed to be relative to the home directory if not
    # already absolute or beginning with "~/".
    my $home = (getpwuid($<))[7];
    $log_dir =~ s{^~/}{$home/};
    unless ($log_dir =~ m{^/}) {
        $log_dir = "$home/$log_dir";
    }
    
    if (mkdir($log_dir)) {
        warn "Made logging directory '$log_dir'\n";
    }
    
    my $log_file = "$log_dir/$file_root.$$.log";
    warn "Logging output to '$log_file'\n";
    Bio::Otter::LogFile->make_log($log_file);
}

sub lock {
    my $self = shift;
    
    confess "lock takes no arguments" if @_;

    return $self->write_access ? 'true' : 'false';
}
sub option_from_array{
    my ($self, $array) = @_;
    return unless $array;
    return Bio::Otter::Lace::Defaults::option_from_array($array);
}
sub client_hostname {
    my( $self, $client_hostname ) = @_;
    
    if ($client_hostname) {
        $self->{'_client_hostname'} = $client_hostname;
    }
    elsif (not $client_hostname = $self->{'_client_hostname'}) {
        $client_hostname = $self->{'_client_hostname'} = hostname();
    }
    return $client_hostname;
}

sub new_AceDatabase {
    my( $self ) = @_;
    
    my $db = Bio::Otter::Lace::AceDatabase->new;
    $db->Client($self);
    my $home = $db->home;
    my $i = ++$self->{'_last_db'};
    $db->home("${home}_$i");
    return $db;
}
sub ace_readonly_tag{
    return Bio::Otter::Lace::AceDatabase::readonly_tag();
}

sub chr_start_end_from_contig {
    my( $self, $ctg ) = @_;
    
    my $chr_name  = $ctg->[0]->chromosome->name;
    my $start     = $ctg->[0]->chr_start;
    my $end       = $ctg->[$#$ctg]->chr_end;
    
    return($chr_name, $start, $end);
}

sub get_DataSet_by_name {
    my( $self, $name ) = @_;
    
    foreach my $ds ($self->get_all_DataSets) {
        if ($ds->name eq $name) {
            return $ds;
        }
    }
    confess "No such DataSet '$name'";
}

sub username{
    my $self = shift;
    warn "get only, use author() method to set" if @_;
    return $self->author();
}
sub password{
    my ($self, $pass) = @_;
    if($pass){
        $self->{'__password'} = $pass;
    }
    return $self->{'__password'} || $self->option_from_array([qw( client password )]);
}
sub password_prompt{
    my ($self, $callback) = @_;
    if($callback){
        $self->{'_password_prompt_callback'} = $callback;
    }
    $callback = $self->{'_password_prompt_callback'};
    unless($callback){
        $callback = sub {
            my $self = shift;
            my $user = $self->username();
            $self->password(Hum::EnsCmdLineDB::prompt_for_password("Please enter your password ($user): "));
        };
        $self->{'_password_prompt_callback'} = $callback;
    }
    return $callback;
}

    # called by AceDatabase.pm:
sub get_xml_for_contig_from_Dataset {
    my( $self, $ctg, $dataset ) = @_;
    
    my ($chr_name, $start, $end) = $self->chr_start_end_from_contig($ctg);
    my $ss = $dataset->selected_SequenceSet
        or confess "no selected_SequenceSet attached to DataSet";
    
    printf STDERR "Fetching data from chr %s %s-%s\n",
        $chr_name, $start, $end;

    return $self->get_xml_from_Dataset_type_chr_start_end(
        $dataset, $ss->name, $chr_name, $start, $end,
    );
}


# ---- HTTP protocol related routines:

sub get_UserAgent {
    my( $self ) = @_;
    
    return LWP::UserAgent->new(timeout => 9000);
}
sub new_http_request{
    my ($self, $method) = @_;
    my $request = HTTP::Request->new();
    $request->method($method || 'GET');

    if(defined(my $password = $self->password())){
        my $encoded = MIME::Base64::encode_base64($self->username() . ":$password");
        $request->header(Authorization => qq`Basic $encoded`);
    }
    return $request;
}
sub url_root {
    my( $self ) = @_;
    
    my $host = $self->host or confess "host not set";
    my $port = $self->port or confess "port not set";
    $port =~ s/\D//g; # port only wants to be a number! no spaces etc
    return "http://$host:$port/perl";
}

=pod 

=head1 _check_for_error

     Args: HTTP::Response Obj, $dont_confess_otter_errors Boolean
  Returns: HTTP::Response->content after checking it for errors
    and "otter" errors.  It will confess (see B<Carp>) the 
    error if there is an error unless Boolean is true, in which 
    case it returns undef. 

=cut

sub _check_for_error {
    my( $self, $response, $dont_confess_otter_errors ) = @_;

    my $xml = $response->content();

    if ($xml =~ m{<response>(.+?)</response>}s) {
        # response can be empty on success
        my $err = $1;
        if($err =~ /\w/){
            return if $dont_confess_otter_errors;
            confess $err;
        }
    }elsif($response->is_error()){
        my $err = $response->message() . "\nServer replied:\n" . $response->content();
        confess $err;
    }
    return $xml;
}

sub general_http_dialog {
    my ($self, $psw_attempts_left, $method, $scriptname, $params) = @_;

    my $url = $self->url_root.'/'.$scriptname;
    my $paramstring = join('&',
        map { $_.'='.uri_escape($params->{$_}) } (keys %$params)
    );
    my $try_password = 0; # first try without it
    my $content      = '';

    do {
        if($try_password++) { # definitely try it next time
            $self->password_prompt()->($self);
            my $pass = $self->password || '';
            warn "Attempting to connect using password '" . '*' x length($pass) . "'\n";
        }
        my $request = $self->new_http_request($method);
        if($method eq 'GET') {
            $request->uri($url.'?'.$paramstring);

            warn "url: ${url}?${paramstring}";
        } elsif($method eq 'POST') {
            $request->uri($url);
            $request->content($paramstring);

            warn "url: $url";
            warn "paramstring: $paramstring";
        } else {
            confess "method '$method' is not supported";
        }
        my $response = $self->get_UserAgent->request($request);
        $content = $self->_check_for_error($response, $psw_attempts_left);
    } while ($psw_attempts_left-- && !$content);

    return $content;
}

# ---- specific HTTP-requests:

sub get_dafs_from_dataset_type_chr_start_end_analysis {
    my( $self, $dataset, $type, $chr_name, $start, $end, $analysis ) = @_;

    my $response = $self->general_http_dialog(
        0,
        'GET',
        'get_dafs',
        {
            'dataset'  => $dataset->name,
            'type'     => $type,
            'chr'      => $chr_name,
            'chrstart' => $start,
            'chrend'   => $end,
            'analysis' => ($analysis ? $analysis : ''),
        }
    );

    my @resplines = split(/\n/,$response);
    pop @resplines; # the last one is empty;

    my @dafs = ();
    foreach my $respline (@resplines) {
        my ($dbID, $hseqname, $hstart, $hend, $hstrand, $start, $end, $strand) = split(/\t/,$respline);
        my $daf = $respline; # FIXME: build a feature here;
        push @dafs, $daf;
    }

    return \@dafs;
}

sub lock_region_for_contig_from_Dataset{
    my( $self, $ctg, $dataset ) = @_;
    
    my ($chr_name, $start, $end) = $self->chr_start_end_from_contig($ctg);
    my $ss = $dataset->selected_SequenceSet
        or confess "no selected_SequenceSet attached to DataSet";
    
    return $self->general_http_dialog(
        0,
        'GET',
        'lock_region',
        {
            'author'   => $self->author,
            'email'    => $self->email,
            'hostname' => $self->client_hostname,
            'dataset'  => $dataset->name,
            'type'     => $ss->name,
            'chr'      => $chr_name,
            'chrstart' => $start,
            'chrend'   => $end,
        }
    );
}

sub get_xml_from_Dataset_type_chr_start_end {
    my( $self, $dataset, $type, $chr_name, $start, $end ) = @_;

    my $xml = $self->general_http_dialog(
        0,
        'GET',
        'get_region',
        {
            'author'   => $self->author,
            'email'    => $self->email,
            'dataset'  => $dataset->name,
            'type'     => $type,
            'chr'      => $chr_name,
            'chrstart' => $start,
            'chrend'   => $end,
        }
    );

    if ($self->debug){
        my $debug_file = Bio::Otter::Lace::PersistentFile->new();
        $debug_file->name("otter-debug.$$.fetch.xml");
        my $fh = $debug_file->write_file_handle();
        print $fh $xml;
        close $fh;
    }else{
        warn "Debug switch is false\n";
    }
    
    return $xml;
}

sub get_all_DataSets {
    my( $self ) = @_;
    
    my $ds = $self->{'_datasets'};
    if (! $ds) {    
        my $content = $self->general_http_dialog(
            3,
            'GET',
            'get_datasets',
            {
                'details' => 'true',
            }
        );

        my $dsp = Bio::Otter::Transform::DataSets->new();
        $dsp->set_property('author', $self->author);
        my $p = $dsp->my_parser();
        $p->parse($content);
        $ds = $self->{'_datasets'} = $dsp->objects;
    }
    return @$ds;
}

sub get_all_SequenceSets_for_DataSet{
    my( $self, $dsObj ) = @_;

    return [] unless $dsObj;
    my $cache = $dsObj->get_all_SequenceSets();
    return $cache if scalar(@$cache);
 
    my $content = $self->general_http_dialog(
        0,
        'GET',
        'get_sequencesets',
        {
            'author'   => $self->author,
            'email'    => $self->email,
            'hostname' => $self->client_hostname,
            'dataset'  => $dsObj->name,
        }
    );
    # stream parsing ????

    my $ssp = Bio::Otter::Transform::SequenceSets->new();
    $ssp->set_property('dataset_name', $dsObj->name);
    my $p   = $ssp->my_parser();
    $p->parse($content);
    return $dsObj->get_all_SequenceSets($ssp->objects);
}

sub save_otter_xml {
    my( $self, $xml, $dataset_name ) = @_;
    
    confess "Don't have write access" unless $self->write_access;
    
    my $content = $self->general_http_dialog(
        0,
        'POST',
        'write_region',
        {
            'author'   => $self->author,
            'email'    => $self->email,
            'dataset'  => $dataset_name,
            'data'     => $xml,
            'unlock'   => 'false',  # We give the annotators the option to
                                    # save during sessions, not just on exit.
        }
    );

    ## return $content;
    ## possibly should be
    return \$content;
}

sub unlock_otter_xml {
    my( $self, $xml, $dataset_name ) = @_;
    
    # print STDERR "<!-- BEGIN XML -->\n" . $xml . "<!-- END XML -->\n\n\n";
    
    my $content = $self->general_http_dialog(
        0,
        'POST',
        'unlock_region',
        {
            'author'   => $self->author,
            'email'    => $self->email,
            'dataset'  => $dataset_name,
            'data'     => $xml,
        }
    );
    return 1;
}

sub dasClient{
    my ($self) = @_;
    my $das_on = $self->option_from_array([qw( client with-das )]);
    my $dasObj;
    if($das_on){
        $dasObj = $self->{'_dasClient'};
        unless($dasObj){
            $dasObj = Bio::Otter::Lace::DasClient->new();
            $self->{'_dasClient'} = $dasObj;
        }
    }else{
        print STDERR "To use Das start '$0 -with-das' (currently in development)\n";
    }
    return $dasObj;
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::Client

=head1 DESCRIPTION

A B<Client> object Communicates with an otter
HTTP server on a particular host and port.  It
has methods to fetch annotated gene information
in otter XML, lock and unlock clones, and save
"ace" formatted annotation back.  It also returns
lists of B<DataSet> objects provided by the
server, and creates B<AceDatabase> objects (which
mangage the acedb database directory structure
for a lace session).

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

