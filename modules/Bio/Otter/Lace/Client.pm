
### Bio::Otter::Lace::Client

package Bio::Otter::Lace::Client;

use strict;
use Carp;
use LWP;
use Bio::Otter::Lace::DataSet;
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

sub new_AceDatabase {
    my( $self ) = @_;
    
    my $db = Bio::Otter::Lace::AceDatabase->new;
    $db->OtterClient($self);
    return $db;
}

sub get_xml_for_contig_from_Dataset {
    my( $self, $ctg, $dataset ) = @_;
    
    my $chr_name  = $ctg->[0]->chromosome->name;
    my $start     = $ctg->[0]->chr_start;
    my $end       = $ctg->[$#$ctg]->chr_end;
    my $root   = $self->url_root;
    my $script = 'get_region';
    my $url = "$root/$script?" .
        uri_escape(
            join('&',
                'author='   . $self->author,
                'email='    . $self->email,
                'lock='     . $self->lock,
                'dataset='  . $dataset->name,
                'chr='      . $chr_name,
                'chrstart=' . $start,
                'chrend='   . $end,
            )
        );
    warn "url <$url>\n";
    
    my $ua = $self->get_UserAgent;
    my $request = HTTP::Request->new;
    $request->method('GET');
    $request->uri($url);
    
    my $content = $ua->request($request)->content;
    $self->_check_for_error(\$content);
    return $content;
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

sub get_all_DataSets {
    my( $self ) = @_;
    
    my( $ds );
    unless ($ds = $self->{'_datasets'}) {    
        my $ua   = $self->get_UserAgent;
        my $root = $self->url_root;
        my $request = HTTP::Request->new;
        $request->method('GET');
        $request->uri("$root/get_datasets?details=true");

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
            my ($name) = /(\S+)/;
            $set->name($name);
            while (/^\s+(\S+)\s+(\S+)/mg) {
                #warn "$name: $1 => $2\n";
                $set->$1($2);
            }
            push(@$ds, $set);
        }
    }
    return @$ds;
}

sub get_UserAgent {
    my( $self ) = @_;
    
    my( $ua );
    unless ($ua = $self->{'_user_agent'}) {
        $ua = $self->{'_user_agent'} = LWP::UserAgent->new;
    }
    return $ua;
}

sub save_otter_ace {
    my( $self, $ace_str, $dataset ) = @_;
    
    confess "Don't have write access" unless $self->write_access;
    
    my $ace = Bio::Otter::Lace::TempFile->new;
    $ace->name('lace_edited.ace');
    my $write = $ace->write_file_handle;
    print $write $ace_str;
    my $xml = Bio::Otter::Converter::ace_to_XML($ace->read_file_handle);
    #print $xml;
    
    # Save to server with POST
    my $url = $self->url_root . '/write_region';
    my $request = HTTP::Request->new;
    $request->method('POST');
    $request->uri($url);
    $request->content(
        uri_escape(
            join('&',
                'author='   . $self->author,
                'email='    . $self->email,
                'dataset='  . $dataset->name,
                'data='     . $xml,
                'unlock=true',  ### May want to provide annotators with
                )               ### option to save during sessions, not
            )                   ### just on exit.
        );
    
    my $content = $self->get_UserAgent->request($request)->content;
    $self->_check_for_error(\$content);
    $self->write_access(0);
    return 1;
}

sub unlock_otter_ace {
    my( $self, $ace_str, $dataset ) = @_;
    
    
}

1;

__END__

=head1 NAME - Bio::Otter::Lace::Client

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

