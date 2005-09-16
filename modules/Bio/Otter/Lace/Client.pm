### Bio::Otter::Lace::Client

package Bio::Otter::Lace::Client;

use strict;
use Carp qw{ confess cluck };
use Sys::Hostname qw{ hostname };
use LWP;
use Symbol 'gensym';
use URI::Escape qw{ uri_escape };
use MIME::Base64;
use Bio::Otter::LogFile;
use Bio::Otter::Lace::DataSet;
use Bio::Otter::Lace::AceDatabase;
use Bio::Otter::Lace::PersistentFile;
use Bio::Otter::Lace::DasClient;
use Bio::Otter::Transform::DataSets;
use Bio::Otter::Transform::SequenceSets;
use Bio::Otter::Converter;
use Bio::Otter::Lace::TempFile;
use Hum::EnsCmdLineDB;

use Bio::Otter::Lace::ViaText ('%OrderOfOptions');
use Bio::EnsEMBL::Analysis;
use Bio::EnsEMBL::DnaDnaAlignFeature;
use Bio::EnsEMBL::DnaPepAlignFeature;
use Bio::Otter::DnaDnaAlignFeature;
use Bio::Otter::DnaPepAlignFeature;
use Bio::EnsEMBL::SimpleFeature;
use Bio::Otter::HitDescription;
use Bio::EnsEMBL::RepeatFeature;
use Bio::EnsEMBL::RepeatConsensus;
use Bio::EnsEMBL::PredictionTranscript;

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

sub get_log_dir {
    my( $self ) = @_;
    
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
    return $log_dir;
}

sub make_log_file {
    my( $self, $file_root ) = @_;
    
    $file_root ||= 'client';
    
    my $log_dir = $self->get_log_dir or return;
    my( $log_file );
    my $i = 'a';
    do {
        $log_file = "$log_dir/$file_root.$$-$i.log";
        $i++;
    } while (-e $log_file);
    warn "Logging output to '$log_file'\n";
    Bio::Otter::LogFile->make_log($log_file);
}

sub cleanup_log_dir {
    my( $self, $file_root, $days ) = @_;
    
    # Files older than this number of days are deleted.
    $days ||= 14;
    
    $file_root ||= 'client';
    
    my $log_dir = $self->get_log_dir or return;
    
    my $LOG = gensym();
    opendir $LOG, $log_dir or confess "Can't open directory '$log_dir': $!";
    foreach my $file (grep /^$file_root\./, readdir $LOG) {
        my $full = "$log_dir/$file";
        if (-M $full > $days) {
            unlink $full
                or warn "Couldn't delete file '$full' : $!";
        }
    }
    closedir $LOG or confess "Error reading directory '$log_dir' : $!";
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
    my( $self, $response, $dont_confess_otter_errors, $unwrap ) = @_;

    my $xml = $response->content();

    if($unwrap && $xml =~ m{<otter[^\>]*\>\s*(.*)</otter>\s*}) {
        $xml = $1;
    }

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
    my ($self, $psw_attempts_left, $method, $scriptname, $params, $unwrap) = @_;

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
            #warn "paramstring: $paramstring";
        } else {
            confess "method '$method' is not supported";
        }
        my $response = $self->get_UserAgent->request($request);
        $content = $self->_check_for_error($response, $psw_attempts_left, $unwrap);
    } while ($psw_attempts_left-- && !$content);

    print "[$scriptname] CLIENT RECEIVED [".length($content)."] bytes over the TCP connection\n";

    return $content;
}

# ---- specific HTTP-requests:

sub get_dafs_from_dataset_slice_analysis {  # get DnaAlignFeatures
    my( $self, $dataset, $slice, $analysis_name, $enshead ) = @_;

    return $self->get_afs_from_dataset_slice_kind_analysis(
        $dataset, $slice, 'dafs', $analysis_name, $enshead
    );
}

sub get_pafs_from_dataset_slice_analysis {  # get ProteinAlignFeatures
    my( $self, $dataset, $slice, $analysis_name, $enshead ) = @_;

    return $self->get_afs_from_dataset_slice_kind_analysis(
        $dataset, $slice, 'pafs', $analysis_name, $enshead
    );
}

sub get_sfs_from_dataset_slice_analysis {   # get SimpleFeatures
    my( $self, $dataset, $slice, $analysis_name, $enshead ) = @_;

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

    my $response = $self->general_http_dialog(
        0,
        'GET',
        'get_sfs',
        {
            'enshead'  => $enshead ? 1 : 0,
            'dataset'  => $dataset->name(),
            'type'     => $slice->assembly_type(),
            'chr'      => $slice->chr_name(),
            'chrstart' => $slice->chr_start(),
            'chrend'   => $slice->chr_end(),
            'analysis' => $analysis_name,
        },
        1,
    );

    my @resplines = split(/\n/,$response);
    pop @resplines; # the last one is empty;  IS IT???

    my @sf_optnames = @{ $OrderOfOptions{SimpleFeature} };

        # cached values:
    my $analysis = Bio::EnsEMBL::Analysis->new( -logic_name => $analysis_name );
    my $seqname = $slice->name();

    my @sfs = (); # simple features in a list
    foreach my $respline (@resplines) {

        my @optvalues = split(/\t/,$respline);
        my $linetype      = shift @optvalues; # 'SimpleFeature'

        my $sf = Bio::EnsEMBL::SimpleFeature->new();

        for my $ind (0..@sf_optnames-1) {
            my $method = $sf_optnames[$ind];
            $sf->$method($optvalues[$ind]);
        }

            # use the cached values:
        $sf->analysis( $analysis );
        $sf->seqname( $seqname );

        push @sfs, $sf;
    }

    return \@sfs;
}

sub get_afs_from_dataset_slice_kind_analysis { # get AlignFeatures (Dna or Protein)
    my( $self, $dataset, $slice, $kind, $analysis_name, $enshead ) = @_;

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

    my ($baseclass, $subclass) = @{ {
        'dafs' => [ qw(Bio::EnsEMBL::DnaDnaAlignFeature Bio::Otter::DnaDnaAlignFeature) ],
        'pafs' => [ qw(Bio::EnsEMBL::DnaPepAlignFeature Bio::Otter::DnaPepAlignFeature) ],
    }->{$kind} };
    
    my $response = $self->general_http_dialog(
        0,
        'GET',
        'get_afs',
        {
            'enshead'  => $enshead ? 1 : 0,
            'dataset'  => $dataset->name(),
            'type'     => $slice->assembly_type(),
            'chr'      => $slice->chr_name(),
            'chrstart' => $slice->chr_start(),
            'chrend'   => $slice->chr_end(),
            'kind'     => $kind,
            'analysis' => $analysis_name,
        },
        1,
    );

    my @resplines = split(/\n/,$response);
    pop @resplines; # the last one is empty;  IS IT???

    my @af_optnames = @{ $OrderOfOptions{AlignFeature} };
    my @hd_optnames = @{ $OrderOfOptions{HitDescription} };

        # cached values:
    my $analysis = Bio::EnsEMBL::Analysis->new( -logic_name => $analysis_name );
    my $seqname = $slice->name();

    my %hds = (); # cached hit descriptions, keyed by hit_name
    my @afs = (); # align features in a list
    foreach my $respline (@resplines) {

        my @optvalues = split(/\t/,$respline);
        my $linetype      = shift @optvalues; # 'AlignFeature' || 'HitDescription'

        if($linetype eq 'HitDescription') {

            my $hit_name = shift @optvalues;
            my $hd = Bio::Otter::HitDescription->new();
            for my $ind (0..@hd_optnames-1) {
                my $method = $hd_optnames[$ind];
                $hd->$method($optvalues[$ind]);
            }
            $hds{$hit_name} = $hd;

        } elsif($linetype eq 'AlignFeature') {
            my $cigar_string  = pop @optvalues;

            my $af = $baseclass->new(
                    -cigar_string => $cigar_string
            );

            for my $ind (0..@af_optnames-1) {
                my $method = $af_optnames[$ind];
                $af->$method($optvalues[$ind]);
            }

                # use the cached values:
            $af->analysis( $analysis );
            $af->seqname( $seqname );

                # Now add the HitDescriptions to Bio::EnsEMBL::DnaXxxAlignFeatures
                # and re-bless them into Bio::Otter::DnaXxxAlignFeatures,
                # IF the HitDescription is available
            my $hit_name = $af->hseqname();
            if(my $hd = $hds{$hit_name}) {
                bless $af, $subclass;
                $af->{'_hit_description'} = $hd;
            } else {
                # warn "No HitDescription for '$hit_name'";
            }

            push @afs, $af;
        }
    }

    return \@afs;
}

sub get_rfs_from_dataset_slice_analysis {   # get RepeatFeatures
    my( $self, $dataset, $slice, $analysis_name, $enshead ) = @_;

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

    my $response = $self->general_http_dialog(
        0,
        'GET',
        'get_rfs',
        {
            'enshead'  => $enshead ? 1 : 0,
            'dataset'  => $dataset->name(),
            'type'     => $slice->assembly_type(),
            'chr'      => $slice->chr_name(),
            'chrstart' => $slice->chr_start(),
            'chrend'   => $slice->chr_end(),
            'analysis' => $analysis_name,
        },
        1,
    );

    my @resplines = split(/\n/,$response);
    pop @resplines; # the last one is empty;  IS IT???

    my @rf_optnames = @{ $OrderOfOptions{RepeatFeature} };
    my @rc_optnames = @{ $OrderOfOptions{RepeatConsensus} };

        # cached values:
    my $analysis = Bio::EnsEMBL::Analysis->new( -logic_name => $analysis_name );

    my %rcs = (); # cached repeat consensi, keyed by rc_id
    my @rfs = (); # repeat features in a list
    foreach my $respline (@resplines) {

        my @optvalues = split(/\t/,$respline);
        my $linetype      = shift @optvalues; # 'RepeatFeature' || 'RepeatConsensus'

        if($linetype eq 'RepeatConsensus') {

            my $rc_id = pop @optvalues;

            my $rc = Bio::EnsEMBL::RepeatConsensus->new();
            for my $ind (0..@rc_optnames-1) {
                my $method = $rc_optnames[$ind];
                $rc->$method($optvalues[$ind]);
            }
            $rcs{$rc_id} = $rc;

        } elsif($linetype eq 'RepeatFeature') {

            my $rc_id = pop @optvalues;

            my $rf = Bio::EnsEMBL::RepeatFeature->new();

            for my $ind (0..@rf_optnames-1) {
                my $method = $rf_optnames[$ind];
                $rf->$method($optvalues[$ind]);
            }

                # use the cached values:
            $rf->analysis( $analysis );
            $rf->repeat_consensus( $rcs{$rc_id} );

            push @rfs, $rf;
        }
    }

    return \@rfs;
}

sub get_pts_from_dataset_slice_analysis {   # get PredictionTranscripts
    my( $self, $dataset, $slice, $analysis_name, $enshead ) = @_;

    if(!$analysis_name) {
        die "Analysis name must be specified!";
    }

    my $response = $self->general_http_dialog(
        0,
        'GET',
        'get_pts',
        {
            'enshead'  => $enshead ? 1 : 0,
            'dataset'  => $dataset->name(),
            'type'     => $slice->assembly_type(),
            'chr'      => $slice->chr_name(),
            'chrstart' => $slice->chr_start(),
            'chrend'   => $slice->chr_end(),
            'analysis' => $analysis_name,
        },
        1,
    );

    my @resplines = split(/\n/,$response);
    pop @resplines; # the last one is empty;  IS IT???


    my @pt_optnames = @{ $OrderOfOptions{PredictionTranscript} };
    my @pe_optnames = @{ $OrderOfOptions{PredictionExon} };

        # cached values:
    my $analysis = Bio::EnsEMBL::Analysis->new( -logic_name => $analysis_name );

    my @pts = (); # prediction transcripts in a list
    my $curr_pt;
    my $curr_ptid;
    foreach my $respline (@resplines) {

        my @optvalues = split(/\t/,$respline);
        my $linetype      = shift @optvalues; # 'PredictionTranscript' || 'PredictionExon'

        if($linetype eq 'PredictionTranscript') {

            my $pt = Bio::EnsEMBL::PredictionTranscript->new();
            for my $ind (0..@pt_optnames-1) {
                my $method = $pt_optnames[$ind];
                $pt->$method($optvalues[$ind]);
            }
            $pt->analysis( $analysis );

            $curr_pt = $pt;
            $curr_ptid = $pt->dbID();

            push @pts, $pt;

        } elsif($linetype eq 'PredictionExon') {

            my $pt_id = pop @optvalues;

            my $pe = Bio::EnsEMBL::Exon->new(); # there is no PredictionExon in v.19 code!

            for my $ind (0..@pe_optnames-1) {
                my $method = $pe_optnames[$ind];
                $pe->$method($optvalues[$ind]);
            }

                # use the cached values:
            $pe->analysis( $analysis );

            if($pt_id == $curr_ptid) {
                $curr_pt->add_Exon( $pe );
            } else {
                die "Wrong order of exons in the stream!";
            }
        }
    }

    return \@pts;
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

