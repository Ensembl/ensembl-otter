
### Bio::Otter::Lace::Client

package Bio::Otter::Lace::Client;

use strict;
use Carp;
use LWP;
use Bio::Otter::Lace::DataSet;
use Bio::Otter::Converter;
use Bio::Otter::Lace::TempFile;

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

sub get_otter_ace {
    my( $self ) = @_;
    
    my $ace = '';
    foreach my $ds ($self->get_all_DataSets) {
        if (my $ctg_list = $ds->selected_CloneSequences_as_contig_list) {
            foreach my $ctg (@$ctg_list) {
                ### It is rather tempting here not to go through the XML layer
                my $xml = Bio::Otter::Lace::TempFile->new;
                $xml->name('lace.xml');
                my $write = $xml->write_file_handle;
                print $write $self->get_xml_for_contig_from_Dataset($ctg, $ds);
                my ($genes, $slice, $sequence, $tiles) =
                    Bio::Otter::Converter::XML_to_otter($xml->read_file_handle);
                $ace .= Bio::Otter::Converter::otter_to_ace($slice, $genes, $tiles, $sequence);
            }
        }
    }
    return $ace;
}

sub save_otter_AcePerl {
    my( $self, $ace_handle, $name ) = @_;
    
    confess "Missing name argument" unless $name;
    
    ### This code should be in a data only module
    $ace->find(Genome_Sequence => $name);
    my $ace_txt = $ace->raw_query('show -a');
    $ace->raw_query('Follow SubSequence');
    $ace_txt .= $ace->raw_query('show -a');
    $ace->raw_query('Follow Locus');
    $ace_txt .= $ace->raw_query('show -a');
    
    # Cleanup text
    $ace_txt =~ s/\0//g;            # Remove nulls
    $ace_txt =~ s{^\s*//.+}{\n}mg;  # Strip comments
    
    return $self->save_otter_ace($ace_txt);
}

sub save_otter_ace {
    my( $self, $ace_str ) = @_;
    
    my $ace = Bio::Otter::Lace::TempFile->new;
    $ace->name('lace_edited.ace');
    my $write = $ace->write_file_handle;
    print $write $ace_str;
    my $xml = Bio::Otter::Converter::ace_to_XML($ace->read_file_handle);
    return $xml;
    
    ### Save to server with POST
}

sub get_xml_for_contig_from_Dataset {
    my( $self, $ctg, $dataset ) = @_;
    
    my $chr_name  = $ctg->[0]->chromosome->name;
    my $start     = $ctg->[0]->chr_start;
    my $end       = $ctg->[$#$ctg]->chr_end;
    my $root   = $self->url_root;
    my $script = 'get_region';
    my $url = "$root/$script?" .
        join('&',
            'author='   . $self->author,
            'email='    . $self->email,
            'lock='     . $self->lock,
            'dataset='  . $dataset->name,
            'chr='      . $chr_name,
            'chrstart=' . $start,
            'chrend='   . $end,
            );
    warn "url <$url>\n";
    
    my $ua = $self->get_UserAgent;
    my $request = HTTP::Request->new;
    $request->method('GET');
    $request->uri($url);
    
    my $response = $ua->request($request);
    unless ($response->is_success) {
        confess "get datasets request failed: ", $response->status_line;
    }
    return $response->content;
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

        my $response = $ua->request($request);
        unless ($response->is_success) {
            confess "get datasets request failed: ", $response->status_line;
        }

        $ds = $self->{'_datasets'} = [];

        my $in_details = 0;
        # Split the string into blocks of text which
        # are separated by two or more newlines.
        foreach (split /\n{2,}/, $response->content) {
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

1;

__END__

=head1 NAME - Bio::Otter::Lace::Client

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

