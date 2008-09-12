### Bio::Otter::Lace::Client

package Bio::Otter::Lace::Client;

use strict;
use warnings;
use Carp qw{ confess cluck };
use Sys::Hostname qw{ hostname };
use LWP;
use Symbol 'gensym';
use URI::Escape qw{ uri_escape };
use MIME::Base64;
use HTTP::Cookies::Netscape;
use Term::ReadKey qw{ ReadMode ReadLine };


use Hum::Conf qw{ PFETCH_SERVER_LIST };

use Bio::Otter::Author;
use Bio::Otter::CloneLock;

use Bio::Otter::Lace::DataSet;
use Bio::Otter::Lace::Locator;
use Bio::Otter::Lace::PersistentFile;
use Bio::Otter::Lace::PipelineStatus;
use Bio::Otter::Lace::SequenceNote;
use Bio::Otter::Lace::TempFile;
use Bio::Otter::LogFile;
use Bio::Otter::Transform::DataSets;
use Bio::Otter::Transform::SequenceSets;
use Bio::Otter::Transform::AccessList;
use Bio::Otter::Transform::CloneSequences;

sub new {
    my( $pkg ) = @_;
    
    $ENV{'OTTERLACE_COOKIE_JAR'} ||= "$ENV{HOME}/.otter/ns_cookie_jar";
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

sub version {
    my( $self, $version ) = @_;
    
    warn "Set using the Config file please.\n" if $version;

    return $self->option_from_array([qw( client version )]);
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

sub client_name {
    my ($self) = @_;
    
    my $name;
    unless ($name = $self->{'_client_name'}) {
        $name = $self->{'_client_name'} = Bio::Otter::Lace::Defaults::client_name();
    }
    return $name;
}

sub debug {
    my ($self, $debug) = @_;

    warn "Set using the Config file please.\n" if $debug;

    my $val = $self->option_from_array([qw( client debug )]);
    return $val ? $val : 0;
}

sub password_attempts {
    my( $self, $password_attempts ) = @_;
    
    if (defined $password_attempts) {
        $self->{'_password_attempts'} = $password_attempts;
    }
    return $self->{'_password_attempts'} || 3;
}

sub timeout_attempts {
    my( $self, $timeout_attempts ) = @_;
    
    if (defined $timeout_attempts) {
        $self->{'_timeout_attempts'} = $timeout_attempts;
    }
    return $self->{'_timeout_attempts'} || 5;
}

sub pfetch_server_pid {
    my( $self, $pfetch_server_pid ) = @_;
    
    if ($pfetch_server_pid) {
        $self->{'_pfetch_server_pid'} = $pfetch_server_pid;
    }
    return $self->{'_pfetch_server_pid'};
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
    if($self->debug()) {
        warn "Logging output to '$log_file'\n";
    }
    Bio::Otter::LogFile::make_log($log_file);
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

#
# now used by scripts only;
# please switch everywhere to using SequenceSet::region_coordinates()
#
sub chr_start_end_from_contig {
    my( $self, $ctg ) = @_;
    
    my $chr_name  = $ctg->[0]->chromosome;
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

sub fork_local_pfetch_server {
    my ($self) = @_;
    
    my ($host, $port) = @{$PFETCH_SERVER_LIST->[0]};
    if ($host ne 'localhost') {
        # Only run local_pfetch if host is set to localhost
        return 0;
    }
    
    if (my $pid = $self->pfetch_server_pid) {
        # 15 is TERM
        kill 15, $pid;
    }
    
    if (my $pid = fork) {
        $self->pfetch_server_pid($pid);
        return 1;
    }
    elsif (defined $pid) {
        no warnings;
        exec('local_pfetch', -port => $port);
        exit(1);    # If exec fails
    }
    else {
        die "Can't fork local_pfetch server: $!";
    }
}

sub password_prompt{
    my ($self, $callback) = @_;
    
    if ($callback) {
        $self->{'_password_prompt_callback'} = $callback;
    }
    $callback = $self->{'_password_prompt_callback'} ||=
        sub {
            my $self = shift;
            
            unless (-t STDIN) {
                warn "Cannot prompt for password - not attached to terminal\n";
                return;
            }
            
            my $user = $self->author;
            print STDERR "Please enter your password ($user): ";
            ReadMode('noecho');
            my $password = ReadLine(0);
            print STDERR "\n";
            chomp $password;
            ReadMode('normal');
            return $password;
        };
    return $callback;
}

sub authorize {
    my ($self) = @_;
    
    my $user = $self->author;
    my $password = $self->password_prompt()->($self)
      or die "No password given";

    # need to url-encode these
    $user     = uri_escape($user);      # possibly not worth it...
    $password = uri_escape($password);  # definitely worth it!

    my $req = HTTP::Request->new;
    $req->method('POST');
    $req->uri("https://enigma.sanger.ac.uk/LOGIN");
    $req->content_type('application/x-www-form-urlencoded');
    $req->content("credential_0=$user&credential_1=$password&destination=/");

    my $web = $self->get_UserAgent;
    my $response = $web->request($req);

    if ($response->is_success) {
        # Cookie will have been given to UserAgent
        warn sprintf "Authorized OK: %s\n",
            $response->status_line;
        $self->fix_cookie_jar_file_permission;
        $web->cookie_jar->save
          or die "Failed to save cookie";
        return 1;
    } else {
        warn sprintf "Authorize failed: %s (%s)\n",
            $response->status_line,
            $response->decoded_content;
        return;
    }
}

# ---- HTTP protocol related routines:

sub get_UserAgent {
    my( $self ) = @_;
    
    my $ua;
    unless ($ua = $self->{'_lwp_useragent'}) {
        $ua = LWP::UserAgent->new(timeout => 9000);
        $ua->env_proxy;
        $ua->protocols_allowed([qw{ http https }]);
        $ua->agent('LoginTest/0.1 ');
        push @{ $ua->requests_redirectable }, 'POST';
        $ua->cookie_jar(HTTP::Cookies::Netscape->new(
            file => $ENV{'OTTERLACE_COOKIE_JAR'},
            ));
    }
    return $ua;
}

sub fix_cookie_jar_file_permission {
    my ($self) = @_;
    
    my $jar = $ENV{'OTTERLACE_COOKIE_JAR'};
    if (-e $jar) {
        # Fix mode if not already mode 600
        my $mode = (stat(_))[2];
        if ($mode != 0600) {
            chmod(0600, $jar) or confess "chmod(0600, '$jar') failed; $!";
        }
    } else {
        # Create file with mode 600
        my $save_mask = umask;
        umask(066);
        open my $fh, "> $jar"
            or confess "Can't create '$jar'; $!";
        umask($save_mask);
    }
}

sub url_root {
    my( $self ) = @_;
    
    my $host    = $self->host    or confess "host not set";
    my $port    = $self->port    or confess "port not set";
    my $version = $self->version or confess "version not set";
    $port =~ s/\D//g; # port only wants to be a number! no spaces etc
    return "http://$host:$port/cgi-bin/otter/$version";
}

# Returns the content string from the http response object
# with the <otter> tags removed.
sub otter_response_content {
    my ($self, $method, $scriptname, $params) = @_;
    
    my $response = $self->general_http_dialog($method, $scriptname, $params);
    
    my $xml = $response->content();

    if (my ($content) = $xml =~ m{<otter[^\>]*\>\s*(.*)</otter>}s) {
        if ($self->debug) {
            warn $self->response_info($scriptname, $params, length($content));
        }
        return $content;
    } else {
        confess "No <otter> tags in response content: [$xml]";
    }
}

# Returns the full content string from the http response object
sub http_response_content {
    my ($self, $method, $scriptname, $params) = @_;
    
    my $response = $self->general_http_dialog($method, $scriptname, $params);
    
    my $xml = $response->content();
    #warn $xml;

    if ($self->debug) {
        warn $self->response_info($scriptname, $params, length($xml));
    }
    return $xml;
}

sub response_info {
    my ($self, $scriptname, $params, $length) = @_;
    
    my $ana = $params->{'analysis'}
      ? ":$params->{analysis}"
      : '';
    return "$scriptname$ana - client received $length bytes from server\n";
}

sub general_http_dialog {
    my ($self, $method, $scriptname, $params) = @_;

    # Set debug to 2 or more to turn on debugging on server side
    $params->{'log'} = 1 if $self->debug > 1;
    $params->{'client'} = $self->client_name;

    my $password_attempts = $self->password_attempts;
    my $timeout_attempts  = $self->timeout_attempts;
    my $response;

    while ($password_attempts and $timeout_attempts) {
        $response = $self->do_http_request($method, $scriptname, $params);
        last if $response->is_success;
        my $code = $response->code;
        if ($code == 401 or $code == 403) {
            # Unauthorized (We are swtiching from 403 to 401 from humpub-release-49.)
            $self->authorize;
            $password_attempts--;
        } elsif ($code == 500 or $code == 502) {
            printf STDERR "\nGot error %s (%s)\nretrying...\n", $code, $response->decoded_content;
            $timeout_attempts--;
        } elsif ($code == 503 or $code == 504) {
            die "The server timed out ($code). Please try again.\n";
        } else {
            confess sprintf "%d (%s)", $response->code, $response->decoded_content;
        }
    }
    return $response;
}

sub escaped_param_string {
    my ($self, $params) = @_;
    
    return join '&', map { $_ . '=' . uri_escape($params->{$_}) } (keys %$params);
}

sub do_http_request {
    my ($self, $method, $scriptname, $params) = @_;

    # Apache non-parsed-header scripts must begin "nph-"
    $scriptname = "nph-$scriptname";

    my $url = $self->url_root.'/'.$scriptname;
    my $paramstring = $self->escaped_param_string($params);

    my $request = HTTP::Request->new;
    $request->method($method);

    if ($method eq 'GET') {
        my $get = $url . ($paramstring ? "?$paramstring" : '');
        $request->uri($get);

        if($self->debug()) {
            warn "GET  $get\n";
        }
    }
    elsif ($method eq 'POST') {
        $request->uri($url);
        $request->content($paramstring);

        if($self->debug()) {
            warn "POST  $url\n";
        }
        #warn "paramstring: $paramstring";
    }
    else {
        confess "method '$method' is not supported";
    }

    return $self->get_UserAgent->request($request);
}

# ---- specific HTTP-requests:

sub to_sliceargs { # not a method!
    my $arg = shift @_;

    return (   UNIVERSAL::isa($arg, 'Bio::EnsEMBL::Slice')
            || UNIVERSAL::isa($arg, 'Bio::Otter::Lace::Slice') )
        ? {
            'cs'    => 'chromosome',
            'csver' => 'Otter',
            'type'  => $arg->assembly_type(),
            'name'  => $arg->chr_name(),
            'start' => $arg->chr_start(),
            'end'   => $arg->chr_end(),
            'slicename' => $arg->name(),
        } : $arg;
}

sub create_detached_slice_from_sa { # not a method!
    my $arg = shift @_;

    if($arg->{cs} ne 'chromosome') {
        die "expecting a slice on a chromosome";
    }

    my $slice = Bio::EnsEMBL::Slice->new(
        -chr_start     => $arg->{start},
        -chr_end       => $arg->{end},
        -chr_name      => $arg->{name},
        -assembly_type => $arg->{type},
    );
    return $slice;
}

=pod

For all of the get_X methods below the 'sliceargs'
is EITHER a valid slice
OR a hash reference that contains enough parameters
to construct the slice for the v20+ EnsEMBL API:

Examples:
    $sa = {
            'cs'    => 'chromosome',
            'name'  => 22,
            'start' => 15e6,
            'end'   => 17e6,
    };
    $sa2 = {
            'cs'    => 'contig',
            'name'  => 'AL008715.1.1.101817',
    }

=cut

sub status_refresh_for_DataSet_SequenceSet{
    my ($self, $ds, $ss) = @_;

    # return unless Bio::Otter::Lace::Defaults::fetch_pipeline_switch();

    my $response = $self->otter_response_content(
        'GET',
        'get_analyses_status',
        {
            'dataset'  => $ds->name(),
            'type'     => $ss->name(),
        },
    );

    my %status_hash = ();
    for my $line (split(/\n/,$response)) {
        my ($c, $a, @rest) = split(/\t/, $line);
        $status_hash{$c}{$a} = \@rest;
    }

    # create a dummy hash with names only:
    my $names_subhash = {};
    if(my ($any_subhash) = (values %status_hash)[0] ) {
        while(my ($ana_name, $values) = each %$any_subhash) {
            $names_subhash->{$ana_name} = [];
        }
    }

    foreach my $cs (@{$ss->CloneSequence_list}) {
        $cs->drop_pipelineStatus;

        my $status = Bio::Otter::Lace::PipelineStatus->new;
        my $contig_name = $cs->contig_name();
        
        my $status_subhash = $status_hash{$contig_name} || $names_subhash;

        if($status_subhash == $names_subhash) {
            warn "had to assign an empty subhash to contig '$contig_name'";
        }

        while(my ($ana_name, $values) = each %$status_subhash) {
            $status->add_analysis($ana_name, $values);
        }

        $cs->pipelineStatus($status);
    }
}

sub find_string_match_in_clones {
    my( $self, $dsname, $qnames_list, $ssname, $unhide_flag ) = @_;

    my $qnames_string = join(',', @$qnames_list);
    my $ds = $self->get_DataSet_by_name($dsname);

    my $response = $self->otter_response_content(
        'GET',
        'find_clones',
        {
            'dataset'  => $dsname,
            'qnames'   => $qnames_string,
            'unhide'   => $unhide_flag || 0,
            defined($ssname) ? ('type' => $ssname ) : (),
        },
    );

    my @results_list = ();

    for my $line (split(/\n/,$response)) {
        my ($qname, $qtype, $component_names, $assembly) = split(/\t/, $line);
        my $component_list = $component_names ? [ split(/,/, $component_names) ] : [];

        push @results_list, Bio::Otter::Lace::Locator->new($qname, $qtype, $component_list, $assembly);
    }

    return \@results_list;
}

sub get_meta {
    my ( $self, $dsname, $which, $key) = @_;

    my $response = $self->otter_response_content(
        'GET',
        'get_meta',
        {
            'dataset'  => $dsname,
            defined($which) ? ('which' => $which ) : (),
            defined($key)   ? ('key' => $key ) : (),
        },
    );

    my $meta_hash = {};
    for my $line (split(/\n/,$response)) {
        my($meta_key, $meta_value) = split(/\t/,$line);
        push @{$meta_hash->{$meta_key}}, $meta_value; # as there can be multiple values for one key
    }

    return $meta_hash;
}

sub lock_refresh_for_DataSet_SequenceSet {
    my( $self, $ds, $ss ) = @_;

    my $response = $self->otter_response_content(
        'GET',
        'get_locks',
        {
            'dataset'  => $ds->name(),
            'type'     => $ss->name(),
        },
    );

    my %lock_hash = ();
    my %author_hash = ();

    for my $line (split(/\n/,$response)) {
        my ($intl_name, $embl_name, $ctg_name, $hostname, $timestamp, $aut_name, $aut_email)
            = split(/\t/, $line);

        $author_hash{$aut_name} ||= Bio::Otter::Author->new(
            -name  => $aut_name,
            -email => $aut_email,
        );

        # Which name should we use as the key? $intl_name or $embl_name?
        #
        # $lock_hash{$intl_name} ||= Bio::Otter::CloneLock->new(
        # $lock_hash{$embl_name} ||= Bio::Otter::CloneLock->new(

        $lock_hash{$ctg_name} ||= Bio::Otter::CloneLock->new(
            -author    => $author_hash{$aut_name},
            -hostname  => $hostname,
            -timestamp => $timestamp,
            # SHOULDN'T WE HAVE ANY REFERENCE TO THE CLONE BEING LOCKED???
        );
    }

    foreach my $cs (@{$ss->CloneSequence_list()}) {
        my $hashkey = $cs->contig_name();

        if(my $lock = $lock_hash{$hashkey}) {
            $cs->set_lock_status($lock);
        } else {
            $cs->set_lock_status(0) ;
        }
    }
}

sub fetch_all_SequenceNotes_for_DataSet_SequenceSet {
    my( $self, $ds, $ss ) = @_;

    $ss ||= $ds->selected_SequenceSet
        || die "no selected_SequenceSet attached to DataSet";

    my $response = $self->otter_response_content(
        'GET',
        'get_sequence_notes',
        {
            'type'     => $ss->name(),
            'dataset'  => $ds->name(),
        },
    );

    my %ctgname2notes = ();

        # we allow the notes to come in any order, so simply fill the hash:
        
    for my $line (split(/\n/,$response)) {
        my ($ctg_name, $aut_name, $is_current, $datetime, $timestamp, $note_text)
            = split(/\t/, $line, 6);

        my $new_note = Bio::Otter::Lace::SequenceNote->new;
        $new_note->text($note_text);
        $new_note->timestamp($timestamp);
        $new_note->is_current($is_current eq 'Y' ? 1 : 0);
        $new_note->author($aut_name);

        my $note_listp = $ctgname2notes{$ctg_name} ||= [];
        push(@$note_listp, $new_note);
    }

        # now, once everything has been loaded, let's fill in the structures:

    foreach my $cs (@{$ss->CloneSequence_list()}) {
        my $hashkey = $cs->contig_name();

        $cs->truncate_SequenceNotes();
        if (my $notes = $ctgname2notes{$hashkey}) {
            foreach my $note (sort {$a->timestamp <=> $b->timestamp} @$notes) {
                # logic in current_SequenceNote doesn't work
                # unless sorting is done first

                $cs->add_SequenceNote($note);
                if ($note->is_current) {
                    $cs->current_SequenceNote($note);
                }
            }
        }
    }

}

sub change_sequence_note {
    my $self = shift @_;

    $self->_sequence_note_action('change', @_);
}

sub push_sequence_note {
    my $self = shift @_;

    $self->_sequence_note_action('push', @_);
}

sub _sequence_note_action {
    my( $self, $action, $dsname, $contig_name, $seq_note ) = @_;

    my $ds = $self->get_DataSet_by_name($dsname);

    my $response = $self->http_response_content(
        'GET',
        'set_sequence_note',
        {
            'dataset'   => $dsname,
            'action'    => $action,
            'contig'    => $contig_name,
            'email'     => $self->email(),
            'timestamp' => $seq_note->timestamp(),
            'text'      => $seq_note->text(),
        },
    );

    # I guess we simply have to ignore the response
}

sub get_all_DataSets {
    my( $self ) = @_;

    my $ds = $self->{'_datasets'};
    if (! $ds) {
      
        my $content = $self->http_response_content(
            'GET',
            'get_datasets',
            {},
        );

        # stream parsing expat non-validating parser
        my $dsp = Bio::Otter::Transform::DataSets->new();
        my $p = $dsp->my_parser();
        $p->parse($content);
        $ds = $self->{'_datasets'} = $dsp->sorted_objects;
        foreach my $dataset (@$ds) {
            $dataset->Client($self);
        }
    }
    return @$ds;
}

sub get_server_otter_config {
    my ($self) = @_;
    
    my $content = $self->http_response_content(
        'GET',
        'get_otter_config',
        {},
    );
    
    Bio::Otter::Lace::Defaults::save_server_otter_config($content);
}

sub do_authentication {
    my ($self) = @_;
    
    my $user = $self->http_response_content(
        'GET',
        'authenticate_me',
        {},
    );
    return $user
}

sub get_all_SequenceSets_for_DataSet {
  my( $self, $ds ) = @_;
  return [] unless $ds;

  my $content = $self->http_response_content(
					   'GET',
					   'get_sequencesets',
					   {
					    'dataset'  => $ds->name(),
					   }
					  );
  # stream parsing expat non-validating parser
  my $ssp = Bio::Otter::Transform::SequenceSets->new();
  $ssp->set_property('dataset_name', $ds->name);
  my $p   = $ssp->my_parser();
  $p->parse($content);
  my $seq_sets = $ssp->objects;

  return $seq_sets;
}

sub get_SequenceSet_AccessList_for_DataSet {
  my ($self,$ds) = @_;
  return [] unless $ds;

  my $content = $self->http_response_content(
					   'GET',
					   'get_sequenceset_accesslist',
					   {
					    'dataset'  => $ds->name,
					   }
					  );
  # stream parsing expat non-validating parser
  my $ssa = Bio::Otter::Transform::AccessList->new();
  my $p   = $ssa->my_parser();
  $p->parse($content);
  my $al=$ssa->objects;
  return $al;
}

sub get_all_CloneSequences_for_DataSet_SequenceSet {
  my( $self, $ds, $ss) = @_;
  return [] unless $ss ;
  my $csl = $ss->CloneSequence_list;
  return $csl if (defined $csl && scalar @$csl);

  my $content = $self->http_response_content(
        'GET',
        # 'get_clonesequences',
        'get_clonesequences_fast',
        {
            'dataset'     => $ds->name(),
            'sequenceset' => $ss->name(),
        }
    );
  # stream parsing expat non-validating parser
  my $csp = Bio::Otter::Transform::CloneSequences->new();
  $csp->my_parser()->parse($content);
  $csl=$csp->objects;
  $ss->CloneSequence_list($csl);
  return $csl;
}

sub get_lace_acedb_tar {
    my ($self) = @_;
    
    # We cache the whole lace_acedb tar.gz file in memory
    unless ($self->{'_lace_acedb_tar'}) {
        $self->{'_lace_acedb_tar'} = $self->http_response_content( 'GET', 'get_lace_acedb_tar', {});
    }
    return $self->{'_lace_acedb_tar'};
}

sub get_methods_ace {
    my ($self) = @_;
    
    # We cache the whole methods.ace file in memory
    unless ($self->{'_methods_ace'}) {
        $self->{'_methods_ace'} = $self->http_response_content('GET', 'get_methods_ace', {});
    }
    return $self->{'_methods_ace'};
}

sub save_otter_xml {
    my( $self, $xml, $dsname ) = @_;
    
    confess "Don't have write access" unless $self->write_access;

    my $ds = $self->get_DataSet_by_name($dsname);
    
    my $content = $self->http_response_content(
        'POST',
        'write_region',
        {
            'email'    => $self->email,
            'dataset'  => $dsname,
            'data'     => $xml,
        }
    );

    ## return $content;
    ## possibly should be
    return \$content;
}

sub unlock_otter_xml {
    my( $self, $xml, $dsname ) = @_;
    
    my $ds = $self->get_DataSet_by_name($dsname);

    $self->general_http_dialog(
        'POST',
        'unlock_region',
        {
            'email'    => $self->email,
            'dataset'  => $dsname,
            'data'     => $xml,
        }
    );
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
server.

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

