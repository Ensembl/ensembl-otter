
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

sub new {
    my( $pkg ) = @_;
    
    return bless {}, $pkg;
}

sub host {
    my( $self, $host ) = @_;
    
    if ($host) {
        $self->{'_host'} = $host;
    }
    return $self->{'_host'};
}

sub port {
    my( $self, $port ) = @_;
    
    if ($port) {
        $self->{'_port'} = $port;
    }
    return $self->{'_port'};
}

sub write_access {
    my( $self, $write_access ) = @_;
    
    if (defined $write_access) {
        $self->{'_write_access'} = $write_access;
    }
    return $self->{'_write_access'} || 0;
}

sub author {
    my( $self, $author ) = @_;
    
    if ($author) {
        $self->{'_author'} = $author;
    }
    return $self->{'_author'} || (getpwuid($<))[6];
}

sub email {
    my( $self, $email ) = @_;
    
    if ($email) {
        $self->{'_email'} = $email;
    }
    return $self->{'_email'} || (getpwuid($<))[0];
}

sub lock {
    my $self = shift;
    
    confess "lock takes no arguments" if @_;
    return $self->write_access ? 'true' : 'false';
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
    my $home = $db->home;
    my $i = ++$self->{'_last_db'};
    $db->home("${home}_$i");
    $db->Client($self);
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
    #warn "url <$url>\n";

    my $ua = $self->get_UserAgent;
    my $request = HTTP::Request->new;
    $request->method('GET');
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
    my( $self, $xml_ref ) = @_;
    
    if ($$xml_ref =~ m{<response>(.+?)</response>}s) {
        # response can be empty on success
        my $err = $1;
        confess $err if $err =~ /\w/;
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
        my $request = HTTP::Request->new;
        $request->method('GET');
        $request->uri("$root/get_datasets?details=true");
        #warn $request->uri;

        my $content = $ua->request($request)->content;
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
    }
    return @$ds;
}

sub save_otter_ace {
    my( $self, $ace_str, $dataset ) = @_;
    
    confess "Don't have write access" unless $self->write_access;
    
    local *DEBUG;
    my $debug_file = "/var/tmp/otter-debug.$$.save.ace";
    open DEBUG, "> $debug_file" or die;
    print DEBUG $ace_str;
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
    my $request = HTTP::Request->new;
    $request->method('POST');
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
    my $url = $self->url_root . '/unlock_region';
    my $request = HTTP::Request->new;
    $request->method('POST');
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

