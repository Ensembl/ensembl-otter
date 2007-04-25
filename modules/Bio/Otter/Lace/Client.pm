### Bio::Otter::Lace::Client

package Bio::Otter::Lace::Client;

use strict;
use Carp qw{ confess cluck };
use Sys::Hostname qw{ hostname };
use LWP;
use Symbol 'gensym';
use URI::Escape qw{ uri_escape };
use MIME::Base64;

use Bio::Otter::Author;
use Bio::Otter::CloneLock;
use Bio::Otter::Converter;
use Bio::Otter::DnaDnaAlignFeature;
use Bio::Otter::DnaPepAlignFeature;
use Bio::Otter::FromXML;
use Bio::Otter::HitDescription;
use Bio::Otter::Lace::AceDatabase;
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

    if($unwrap && $xml =~ m{<otter[^\>]*\>\s*(.*)</otter>\s*}s) {
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
        if ($method eq 'GET') {
            my $get = $url . ($paramstring ? "?$paramstring" : '');
            $request->uri($get);
            if($self->debug()) {
                warn "GET  $get\n";
            }
        } elsif ($method eq 'POST') {
            $request->uri($url);
            $request->content($paramstring);

            if($self->debug()) {
                warn "POST  $url\n";
            }
            #warn "paramstring: $paramstring";
        } else {
            confess "method '$method' is not supported";
        }

        my $response = $self->get_UserAgent->request($request);
        $content = $self->_check_for_error($response, $psw_attempts_left, $unwrap);
    } while ($psw_attempts_left-- && !$content);

    if($self->debug()) {
        warn "[$scriptname"
              .($params->{analysis} ? ':'.$params->{analysis} : '')
              ."] CLIENT RECEIVED ["
              .length($content)
              ."] bytes over the TCP connection\n\n";
    }

    return $content;
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

    return unless Bio::Otter::Lace::Defaults::fetch_pipeline_switch();

    my $pipehead = Bio::Otter::Lace::Defaults::pipehead();

    my $response = $self->general_http_dialog(
        0,
        'GET',
        'get_analyses_status',
        {
            'dataset'  => $ds->name(),
            'type'     => $ss->name(),
            'pipehead'  => $pipehead ? 1 : 0,
        },
        1,
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

    my $response = $self->general_http_dialog(
        0,
        'GET',
        'find_clones',
        {
            'dataset'  => $dsname,
            'pipehead' => $ds->HEADCODE(),
            'qnames'   => $qnames_string,
            'unhide'   => $unhide_flag || 0,
            defined($ssname) ? ('type' => $ssname ) : (),
        },
        1,
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

    my $pipehead = Bio::Otter::Lace::Defaults::pipehead();

    my $response = $self->general_http_dialog(
        0,
        'GET',
        'get_meta',
        {
            'dataset'  => $dsname,
            defined($which) ? ('which' => $which ) : (),
            defined($key)   ? ('key' => $key ) : (),
            'pipehead'  => $pipehead ? 1 : 0,
        },
        1,
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

    my $response = $self->general_http_dialog(
        0,
        'GET',
        'get_locks',
        {
            'dataset'  => $ds->name(),
            'type'     => $ss->name(),
            'pipehead' => $ds->HEADCODE(),
        },
        1,
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

    my $response = $self->general_http_dialog(
        0,
        'GET',
        'get_sequence_notes',
        {
            'type'     => $ss->name(),
            'dataset'  => $ds->name(),
            'pipehead' => $ds->HEADCODE(),
        },
        1,
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

    my $response = $self->general_http_dialog(
        0,
        'GET',
        'set_sequence_note',
        {
            'dataset'   => $dsname,
            'pipehead'  => $ds->HEADCODE(),
            'action'    => $action,
            'contig'    => $contig_name,
            'author'    => $self->author(), # should be identical to the note's author
            'email'     => $self->email(),
            'timestamp' => $seq_note->timestamp(),
            'text'      => $seq_note->text(),
        },
        1,
    );

    # I guess we simply have to ignore the response
}

sub lock_region {
    my($self, $dsname, $ssname, $chr_name, $chr_start, $chr_end ) = @_;
    
    my $ds = $self->get_DataSet_by_name($dsname);

    return $self->general_http_dialog(
        0,
        'GET',
        'lock_region',
        {
            'author'   => $self->author,
            'email'    => $self->email,
            'hostname' => $self->client_hostname,
            'dataset'  => $dsname,
            'type'     => $ssname,
            'name'     => $chr_name,
            'start'    => $chr_start,
            'end'      => $chr_end,
            'pipehead' => $ds->HEADCODE(),
        }
    );
}

sub get_xml_region {
    my( $self, $dsname, $ssname, $chr_name, $chr_start, $chr_end ) = @_;

    if($self->debug()) {
        warn sprintf("Fetching data from chr %s %s-%s\n", $chr_name, $chr_start, $chr_end);
    }

    my $ds = $self->get_DataSet_by_name($dsname);

    my $xml = $self->general_http_dialog(
        0,
        'GET',
        'get_region',
        {
            'author'   => $self->author,
            'email'    => $self->email,
            'dataset'  => $dsname,
            'type'     => $ssname,
            'name'     => $chr_name,
            'start'    => $chr_start,
            'end'      => $chr_end,
            'pipehead' => $ds->HEADCODE(),
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

sub get_all_SequenceSets_for_DataSet {
  my( $self, $ds ) = @_;
  return [] unless $ds;

  my $content = $self->general_http_dialog(
					   3,
					   'GET',
					   'get_sequencesets',
					   {
					    'author'   => $self->author,
					    'dataset'  => $ds->name(),
                        'pipehead' => $ds->HEADCODE(),
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

  my $content = $self->general_http_dialog(
					   3,
					   'GET',
					   'get_sequenceset_accesslist',
					   {
					    'author'   => $self->author,
					    'dataset'  => $ds->name,
                        'pipehead' => $ds->HEADCODE(),
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

  my $content = $self->general_http_dialog(
                                           3,
                                           'GET',
                                           'get_clonesequences',
                                           {
                                            'author'      => $self->author(),
                                            'dataset'     => $ds->name(),
                                            'sequenceset' => $ss->name(),
                                            'pipehead'    => $ds->HEADCODE(),
                                           }
                                          );
  # stream parsing expat non-validating parser
  my $csp = Bio::Otter::Transform::CloneSequences->new();
  $csp->my_parser()->parse($content);
  $csl=$csp->objects;
  $ss->CloneSequence_list($csl);
  return $csl;
}

sub save_otter_xml {
    my( $self, $xml, $dsname ) = @_;
    
    confess "Don't have write access" unless $self->write_access;

    my $ds = $self->get_DataSet_by_name($dsname);
    
    my $content = $self->general_http_dialog(
        0,
        'POST',
        'write_region',
        {
            'author'   => $self->author,
            'email'    => $self->email,
            'dataset'  => $dsname,
            'pipehead' => $ds->HEADCODE(),
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

    my $content = $self->general_http_dialog(
        0,
        'POST',
        'unlock_region',
        {
            'author'   => $self->author,
            'email'    => $self->email,
            'dataset'  => $dsname,
            'pipehead' => $ds->HEADCODE(),
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
server, and creates B<AceDatabase> objects (which
mangage the acedb database directory structure
for a lace session).

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

