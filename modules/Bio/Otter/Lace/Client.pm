
### Bio::Otter::Lace::Client

package Bio::Otter::Lace::Client;

use strict;
use Carp qw{ confess cluck };
use Sys::Hostname qw{ hostname };
use LWP;
use Bio::Otter::Lace::DataSet;
use Bio::Otter::Lace::AceDatabase;
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
    
    if ($host) {
        $self->{'_options'}->{'client'}->{'host'} = $host;
    }
    return $self->{'_options'}->{'client'}->{'host'};
}
sub readonly_tag {
    my( $self, $ro ) = @_;
    
    if ($ro) {
        $self->{'_options'}->{'client'}->{'readonly_tag'} = $ro;
    }
    return $self->{'_options'}->{'client'}->{'readonly_tag'} || '';
}
sub port {
    my( $self, $port ) = @_;
    
    if ($port) {
        $self->{'_options'}->{'client'}->{'port'} = $port;
    }
    return $self->{'_options'}->{'client'}->{'port'};
}

sub write_access {
    my( $self, $write_access ) = @_;
    
    if (defined $write_access) {
        $self->{'_options'}->{'client'}->{'write_access'} = $write_access;
    }
    return $self->{'_options'}->{'client'}->{'write_access'} || 0;
}

sub author {
    my( $self, $author ) = @_;
    
    if ($author) {
        $self->{'_options'}->{'client'}->{'author'} = $author;
    }
    return $self->{'_options'}->{'client'}->{'author'} || (getpwuid($<))[6];
}

sub email {
    my( $self, $email ) = @_;
    
    if ($email) {
        $self->{'_options'}->{'client'}->{'email'} = $email;
    }
    return $self->{'_options'}->{'client'}->{'email'} || (getpwuid($<))[0];
}

sub lock {
    my $self = shift;
    
    confess "lock takes no arguments" if @_;
    return $self->write_access ? 'true' : 'false';
}
sub all_options{
    my ($self, $hash) = @_;
    $self->{'_options'} = $hash if ref($hash) eq 'HASH';
    return $self->{'_options'};
}

sub option_from_array{
    my ($self, $array) = @_;
    my $options = $self->all_options();
    my $opt     = $options;
    my $key     = pop @$array;
    my $value   = undef;

    foreach my $k(@$array){
	if(exists $opt->{$k}){
	    $opt = $opt->{$k};
	}else{
	    warn "Couldn't find $k. Please check otter_config file\n";
	    next;
	}
    }
    $value = $opt->{$key};
    return $value;
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

sub get_UserAgent {
    my( $self ) = @_;
    
    return LWP::UserAgent->new(timeout => 9000);

    #my( $ua );
    #unless ($ua = $self->{'_user_agent'}) {
    #    $ua = $self->{'_user_agent'} = LWP::UserAgent->new;
    #}
    #return $ua;
}

sub get_xml_for_contig_from_Dataset {
    my( $self, $ctg, $dataset ) = @_;
    
    my $chr_name  = $ctg->[0]->chromosome->name;
    my $start     = $ctg->[0]->chr_start;
    my $end       = $ctg->[$#$ctg]->chr_end;
    my $ss = $dataset->selected_SequenceSet
        or confess "no selected_SequenceSet attached to DataSet";
    
    printf STDERR "Fetching data from chr %s %s-%s (lock='%s')\n",
        $chr_name, $start, $end, $self->lock;
    
    my $root   = $self->url_root;
    my $url = "$root/get_region?" .
        join('&',
	     'author='   . uri_escape($self->author),
	     'email='    . uri_escape($self->email),
	     'lock='     . uri_escape($self->lock),
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

    my $xml = $ua->request($request)->content;
    #warn $xml;
    $self->_check_for_error(\$xml);
    
    my $debug_file = "/var/tmp/otter-debug.$$.fetch.xml";
    open DEBUG, "> $debug_file" or die;
    print DEBUG $xml;
    close DEBUG;
    
    return $xml;
}

sub _check_for_error {
    my( $self, $xml_ref, $return_instead_of_confessing ) = @_;
    
    if ($$xml_ref =~ m{<response>(.+?)</response>}s) {
        # response can be empty on success
        my $err = $1;
        if($err =~ /\w/){
            return 0 if $return_instead_of_confessing;
            confess $err;
        }
    }
    return 1;
}

sub url_root {
    my( $self ) = @_;
    
    my $host = $self->host or confess "host not set";
    my $port = $self->port or confess "port not set";
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
        my $content;
        for(my $i = 0 ; $i <= 3 ; $i++){
            if($i > 0){
                my $pass = $self->password_prompt();
                #warn "Attempting to connect using password '" . '*' x length($pass) . "'\n";
                $self->password($pass);
            }
            my $request = $self->new_http_request('GET');
            $request->uri("$root/get_datasets?details=true");
            #warn $request->uri();
            $content = $ua->request($request)->content;
            last if $self->_check_for_error(\$content,1);
        }
        $self->_check_for_error(\$content);
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

sub save_otter_ace {
    my( $self, $ace_str, $dataset ) = @_;
    
    confess "Don't have write access" unless $self->write_access;
    
    local *DEBUG;
    my $debug_file = "/var/tmp/otter-debug.$$.save.ace";
    open DEBUG, "> $debug_file" or die;
#    print DEBUG $ace_str;
    close DEBUG;
    
    my $ace = Bio::Otter::Lace::TempFile->new;
    $ace->name('lace_edited.ace');
    my $write = $ace->write_file_handle;
    print $write $ace_str;
    my $xml = Bio::Otter::Converter::ace_to_XML($ace->read_file_handle);
    
    $debug_file = "/var/tmp/otter-debug.$$.save.xml";
    open DEBUG, "> $debug_file" or die;
    print DEBUG $xml;
    close DEBUG;
    
    # Save to server with POST
    my $url = $self->url_root . '/write_region';
    my $request = $self->new_http_request('POST');
    $request->uri($url);
    $request->content(
        join('&',
            'author='   . uri_escape($self->author),
            'email='    . uri_escape($self->email),
            'dataset='  . uri_escape($dataset->name),
            'data='     . uri_escape($xml),
            'unlock=false',     # We give the annotators the option to
            )                   # save during sessions, not just on exit.
        );
    
    my $content = $self->get_UserAgent->request($request)->content;
    $self->_check_for_error(\$content);
    return 1;
}


sub unlock_otter_ace {
    my( $self, $ace_str, $dataset ) = @_;
    
    #cluck "Unlocking ", substr($ace_str, 0, 80);
    
    my $ace = Bio::Otter::Lace::TempFile->new;
    $ace->name('lace_unlock_contig.ace');
    my $write = $ace->write_file_handle;
    print $write $ace_str;
    my $xml = Bio::Otter::Converter::ace_to_XML($ace->read_file_handle);
    
    #print STDERR $xml;
    
    # Save to server with POST
    return $self->_send_to_server($xml , $dataset);

}

# saves some code replication between unlock_otter_ace and remove_stale_locks  
sub _send_to_server{
    my ($self , $xml , $dataset ) =@_ ;
    
    my $url = $self->url_root . '/unlock_region';
    my $request = $self->new_http_request('POST');
    $request->uri($url);
    
    $request->content(
        join('&',
            'author='   . uri_escape($self->author),
            'email='    . uri_escape($self->email),
            'dataset='  . uri_escape($dataset->name),
            'data='     . uri_escape($xml),
            )
        );
    
    my $content = $self->get_UserAgent->request($request)->content;
    
    $self->_check_for_error(\$content);
    return 1;
}


# this method is used when a lace session has failed to open, and has left locks behind
# It takes the sequence set (with the 'locked' clones as the selected_CloneSequences)
sub remove_stale_locks {
    my( $self,  $ss , $dataset) = @_;

    my $xml ;
    foreach my $cs ( @{ $ss->selected_CloneSequences }){
        $xml .= $self->_xml_string($cs , $ss->name);    
    }
    
    return $self->_send_to_server($xml , $dataset) ;
}

## used to produce the relevant XML for the 'remove_stale_locks' method above
sub _xml_string{
    my ($self, $contig, $ss_name) = @_ ;
       
    my $xml_string = "<otter>
    <sequence_set>
      <assembly_type>" . $ss_name . "</assembly_type>
        <sequence_fragment>
            <id>" . $contig->contig_name . "</id>
            <chromosome>" . $contig->chromosome->name . "</chromosome>
            <accession>" . $contig->accession . "</accession>
            <assembly_start>" . $contig->chr_start . "</assembly_start>
            <assembly_end>" . $contig->chr_end ."</assembly_end>
        </sequence_fragment> 
    </sequence_set>
    </otter>" ;

    return $xml_string ;
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
    warn "GET only, user author() method to set" if @_;
    return $self->author();
}
sub password{
    my ($self, $pass) = @_;
    $self->{'_options'}->{'client'}->{'password'} = $pass if defined($pass);
    return $self->{'_options'}->{'client'}->{'password'};
}
sub password_prompt{
    my $self = shift;
    my $user = $self->username();
    return Hum::EnsCmdLineDB::prompt_for_password("Please enter your password ($user): ");
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

