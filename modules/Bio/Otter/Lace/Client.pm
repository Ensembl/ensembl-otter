
### Bio::Otter::Lace::Client

package Bio::Otter::Lace::Client;

use strict;
use Carp qw{ confess cluck };
use Sys::Hostname qw{ hostname };
use LWP;
use Bio::Otter::Lace::DataSet;
use Bio::Otter::Lace::AceDatabase;
use Bio::Otter::Lace::PersistentFile;
use Bio::Otter::Lace::DasClient;
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
sub get_UserAgent {
    my( $self ) = @_;
    
    return LWP::UserAgent->new(timeout => 9000);

    #my( $ua );
    #unless ($ua = $self->{'_user_agent'}) {
    #    $ua = $self->{'_user_agent'} = LWP::UserAgent->new;
    #}
    #return $ua;
}
sub lock_region_for_contig_from_Dataset{
    my( $self, $ctg, $dataset ) = @_;
    
    my $chr_name  = $ctg->[0]->chromosome->name;
    my $start     = $ctg->[0]->chr_start;
    my $end       = $ctg->[$#$ctg]->chr_end;
    my $ss = $dataset->selected_SequenceSet
        or confess "no selected_SequenceSet attached to DataSet";
    
    my $root   = $self->url_root;
    my $url = "$root/lock_region?" .
        join('&',
	     'author='   . uri_escape($self->author),
	     'email='    . uri_escape($self->email),
             'hostname=' . uri_escape($self->client_hostname),
	     'dataset='  . uri_escape($dataset->name),
	     'chr='      . uri_escape($chr_name),
	     'chrstart=' . uri_escape($start),
	     'chrend='   . uri_escape($end),
             'type='     . uri_escape($ss->name),
	     );
    warn "url <$url>\n";

    my $ua = $self->get_UserAgent;
    my $request = $self->new_http_request('GET');
    $request->uri($url);
    my $response = $ua->request($request);

    my $xml = $self->_check_for_error($response);

    return $xml;
}
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

sub get_xml_from_Dataset_type_chr_start_end {
    my( $self, $dataset, $type, $chr_name, $start, $end ) = @_;
    
    my $root = $self->url_root;
    my $url = "$root/get_region?" .
        join('&',
	     'author='   . uri_escape($self->author),
	     'email='    . uri_escape($self->email),
	     'dataset='  . uri_escape($dataset->name),
	     'chr='      . uri_escape($chr_name),
	     'chrstart=' . uri_escape($start),
	     'chrend='   . uri_escape($end),
             'type='     . uri_escape($type),
	     );
    warn "url <$url>\n";

    my $ua = $self->get_UserAgent;
    my $request = $self->new_http_request('GET');
    $request->uri($url);
    my $response = $ua->request($request);

    my $xml = $self->_check_for_error($response);

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

sub chr_start_end_from_contig {
    my( $self, $ctg ) = @_;
    
    my $chr_name  = $ctg->[0]->chromosome->name;
    my $start     = $ctg->[0]->chr_start;
    my $end       = $ctg->[$#$ctg]->chr_end;
    
    return($chr_name, $start, $end);
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

sub url_root {
    my( $self ) = @_;
    
    my $host = $self->host or confess "host not set";
    my $port = $self->port or confess "port not set";
    $port =~ s/\D//g; # port only wants to be a number! no spaces etc
    return "http://$host:$port/perl";
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

sub get_all_DataSets {
    my( $self ) = @_;
    
    my( $ds );
    unless ($ds = $self->{'_datasets'}) {    
        my $ua   = $self->get_UserAgent;
        my $root = $self->url_root;
        my ($content, $response);
        for(my $i = 0 ; $i <= 3 ; $i++){
            if($i > 0){
                my $pass = $self->password_prompt();
                #warn "Attempting to connect using password '" . '*' x length($pass) . "'\n";
                $self->password($pass);
            }
            my $request = $self->new_http_request('GET');
            $request->uri("$root/get_datasets?details=true");
            # warn $request->uri();
            $response   = $ua->request($request);
            last if $content = $self->_check_for_error($response, 1);
        }
        $self->_check_for_error($response);
        $response = undef;
        $ds = $self->{'_datasets'} = [];

        my $in_details = 0;
        # Split the string into blocks of text which
        # are separated by two or more newlines.
        foreach (split /\n{2,}/, $content) {
            if (/Details/) {
                $in_details = 1;
                next;
            }
            next unless $in_details;

            my $set = Bio::Otter::Lace::DataSet->new;
            $set->author($self->author);
            my ($name) = /(\S+)/;
            $set->name($name);
            my $property_count = 0;
            while (/^\s+(\S+)\s+(\S+)/mg) {
                $property_count++;
                #warn "$name: $1 => $2\n";
                $set->$1($2);
            }
            confess "No properties in dataset '$name'" unless $property_count;
            push(@$ds, $set);
        }
        ### Would prefer to keep order found in species.dat
        @$ds = sort {$a->name cmp $b->name} @$ds;
    }
    return @$ds;
}

sub save_otter_xml {
    my( $self, $xml, $dataset_name ) = @_;
    
    confess "Don't have write access" unless $self->write_access;
    
    # Save to server with POST
    my $url = $self->url_root . '/write_region';
    my $request = $self->new_http_request('POST');
    $request->uri($url);
    $request->content(
        join('&',
            'author='   . uri_escape($self->author),
            'email='    . uri_escape($self->email),
            'dataset='  . uri_escape($dataset_name),
            'data='     . uri_escape($xml),
            'unlock=false',     # We give the annotators the option to
            )                   # save during sessions, not just on exit.
        );
    my $response = $self->get_UserAgent->request($request);
    my $content  = $self->_check_for_error($response);

    ## return $content;
    ## possibly should be
    return \$content;
}


sub unlock_otter_xml {
    my( $self, $xml, $dataset_name ) = @_;
    
    # print STDERR "<!-- BEGIN XML -->\n" . $xml . "<!-- END XML -->\n\n\n";
    
    # Save to server with POST
    my $url = $self->url_root . '/unlock_region';
    my $request = $self->new_http_request('POST');
    $request->uri($url);
    
    $request->content(
        join('&',
            'author='   . uri_escape($self->author),
            'email='    . uri_escape($self->email),
            'dataset='  . uri_escape($dataset_name),
            'data='     . uri_escape($xml),
            )
        );
    my $response = $self->get_UserAgent->request($request);
    my $content  = $self->_check_for_error($response);
    return 1;
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
sub username{
    my $self = shift;
    warn "GET only, use author() method to set" if @_;
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
            return Hum::EnsCmdLineDB::prompt_for_password("Please enter your password ($user): ");
        };
        $self->{'_password_prompt_callback'} = $callback;
    }
    return $callback->($self);
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

