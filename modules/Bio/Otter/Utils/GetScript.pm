=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Bio::Otter::Utils::GetScript;

# Lightweight helper for filter_get and friends

use strict;
use warnings;

use Carp;
use IO::Handle;
use Scalar::Util qw(weaken);
use Time::HiRes qw( time gettimeofday );
use URI::Escape  qw(uri_escape uri_unescape);
use Bio::Otter::Utils::TimeDiff;

use constant _DEBUG_INCS => $ENV{OTTER_DEBUG_INCS}; ## no critic(ValuesAndExpressions::ProhibitConstantPragma)

BEGIN {
    require Data::Dumper if _DEBUG_INCS;
}

sub log_incs {
    my ($helper, $header) = @_;
    if (_DEBUG_INCS) {
        my $dump = Data::Dumper->Dump([\%INC], [qw(*INC)]);
        $helper->log_message("${header} ${dump}");
    }
    return;
}

# Deferred until needed on cache miss.
# Augment in child if necessary.
# Less general modules may be require'd by methods as required below.
#
sub do_requires {
    require DBI;
    require Bio::Otter::Lace::DB;
    require Bio::Otter::Lace::DB::ColumnAdaptor;
    return;
}

# Override in child if necessary.
#
sub log_context {
    my ($self) = @_;
    return $self->arg('gff_source') || ref($self); 
}

# NB GetScript is a singleton...

my $me;

# ...hence these class members are simple variables.

my $getscript_log_context = 'not-set';
my $getscript_session_dir;
my $getscript_local_db;
my $getscript_log4perl_level;
my $getscript_user_agent;
my $getscript_url_root;

my %getscript_args;

sub new {
    my ($pkg, %opts) = @_;

    die "GetScript object already instantiated" if $me;
    my $ref = "";
    $me = bless \$ref, $pkg;

    $getscript_log4perl_level = $opts{log4perl};

    weaken $me;                 # else will not be DESTROYed until program exit
    return $me;
}

sub run {
    my ($self) = @_;
    
    my $args = $self->_parse_uri_style_args;

    $self->show_version if exists $args->{'version'};   # exits
    die "failing as required" if $args->{'fail'};       # test case

    if (my $dir = $self->read_delete_args('session_dir')) {
        $self->_use_session_dir($dir);
    }

    $self->_set_log_context($self->log_context);
    $self->_open_log($self->log_filename);

    if ($getscript_log4perl_level) {
        require Bio::Otter::Log::Log4perl;
        require Log::Log4perl::Layout::NoopLayout;

        my $appender = Log::Log4perl::Appender->new('Bio::Otter::Utils::GetScript::Log4perlAppender');
        $appender->layout(Log::Log4perl::Layout::NoopLayout->new());

        my $log = Log::Log4perl->get_logger(''); # must specify '' for root logger
        $log->add_appender($appender);
        $log->level($getscript_log4perl_level);
        $log->debug('Log4perl ready');
    }

    $self->log_message("starting");
    $self->log_incs('After startup');
    $self->_log_arguments;

    $self->do_it;

    $self->log_message("finished");
    return;
}

sub show_version {
    my ($self) = @_;

    # Ensure dependencies are all met
    $self->do_requires;
    my $dbh = DBI->connect("dbi:SQLite:dbname=:memory:","","");

    print $self->version, "\n";
    exit 0;
}

sub _set_log_context {
    my ($self, $context) = @_;
    return $getscript_log_context = $context;
}

sub _parse_uri_style_args {
    my ($self) = @_;

    foreach my $pair (@ARGV) {
        my ($key, $val) = split(/=/, $pair);
        $key =~ s/^-{1,2}//;    # Remove (up to two) minus signs from --opt=val style arguments
        $getscript_args{uri_unescape($key)} = uri_unescape($val);
    }
    return \%getscript_args;
}

sub args {
    return \%getscript_args;
}

sub read_args {
    my ($self, @wanted) = @_;
    return @getscript_args{@wanted};
}

sub read_delete_args {
    my ($self, @wanted) = @_;
    return delete @getscript_args{@wanted};
}

sub require_arg {
    my ($self, $key) = @_;
    confess "No argument '$key'" unless exists $getscript_args{$key};
    return $getscript_args{$key};
}

sub arg {
    my ($self, $key) = @_;
    return $getscript_args{$key};
}

sub format_params {
    my ($self, $args) = @_;

    return join '&', map {
        uri_escape($_) . '=' . uri_escape($args->{$_});
    } sort keys %$args;
}

sub _log_arguments {
    my ($self) = @_;
    $self->log_message(sprintf "argument: %s: %s", $_, $getscript_args{$_}) for sort keys %getscript_args;
    return;
}

sub _use_session_dir {
    my ($self, $sda) = @_;
    $getscript_session_dir = $sda;
    die "No session_dir argument" unless $getscript_session_dir;
    chdir($getscript_session_dir) or die "Could not chdir to '$getscript_session_dir'; $!";
    return $getscript_session_dir;
}

sub mkdir_tested {
    my ($self, $dir_path) = @_;
    unless (-d $dir_path) {
        # Cannot check return value from mkdir() because another instance of the
        # script is likely to have made the directory since many run in parallel!
        mkdir $dir_path;
        unless (-d $dir_path) {
            die "Failed to create toplevel cache directory: $!\n";
        }
    }
    return $dir_path;
}

{
    my $log_file;

    sub _open_log {
        my ($self, $log_path) = @_;
        open $log_file, '>>', $log_path
            or die "failed to open the log file '${log_path}'";
        $log_file->autoflush(1);
        return $log_file;
    }

    # Not a method
    sub _log_prefix {
        my ($sec, $micro) = gettimeofday();
        my @t = localtime($sec);
        my @date = ( 1900+$t[5], $t[4]+1, @t[3,2,1,0] );
        return sprintf "%4d-%02d-%02d %02d:%02d:%02d,%04.0f: %6d: %-35s ",
          @date, $micro / 100, $$, $getscript_log_context;
    }

    sub log_message {
        my ($self, $message) = @_;
        return unless $log_file;
        printf $log_file "%s: %s\n", _log_prefix, $message;
        return;
    }

    sub log_chunk {
        my ($self, $prefix, $chunk) = @_;
        return unless $log_file;
        my $prefix_full = sprintf "%s: %s: ", _log_prefix, $prefix;
        chomp $chunk;
        $chunk .= "\n";
        $chunk =~ s/^/$prefix_full/gm;
        print $log_file $chunk;
        return;
    }
}

sub time_diff_for {
    my ($self, $log, $code) = @_;
    Bio::Otter::Utils::TimeDiff::time_diff_for($code, sub { $self->_time_diff_log(@_) }, $log);
    return;
}

sub _time_diff_log {
    my ($self, $event, $data, $cb_data) = @_;
    if ($event eq 'elapsed') {
        $self->log_message("${cb_data}: ${event} (sec): $data");
    } else {
        $self->log_message("${cb_data}: ${event}");
    }
    return;
}

sub local_db {
    my ($self) = @_;

    return $getscript_local_db if $getscript_local_db;

    return $getscript_local_db = Bio::Otter::Lace::DB->new(
        home    => $getscript_session_dir,
        species => $self->arg('dataset'),
        );
}

sub update_local_db {
    my ($self, $column_name, $cache_file, $process_gff) = @_;

    $self->time_diff_for('SQLite update', sub {
        my $dbh = $self->local_db->dbh;
        my $db_filter_adaptor = Bio::Otter::Lace::DB::ColumnAdaptor->new($dbh);
        ## no critic (Anacode::ProhibitEval)
        unless (eval {
            # No transaction!  Make only one statement.  Transactions
            # require more complex retrying when database is busy.
            my $rv = $db_filter_adaptor->update_for_filter_script(
                $column_name, # WHERE: name
                $cache_file,  # SET: gff_file,
                $process_gff, #      process_gff,
                              #      status = 'Loading'
                );
            die "Changed $rv rows" unless 1 == $rv;
            1;
             } ) {
            my $err = $@;
            my $msg = "Update of otter_column table in SQLite db failed; $err";
            $self->log_message($msg);
            die $msg;
        }
        $dbh->disconnect;
    } );
    return;
}

sub user_agent {
    my ($self) = @_;
    return $getscript_user_agent if $getscript_user_agent;

    require LWP::UserAgent;
    require HTTP::Request;      # although we use it below, not here.

    $getscript_user_agent = LWP::UserAgent->new(
        timeout             => 9000,
        env_proxy           => 1,
        agent               => $0,
        protocols_allowed   => [qw(http https)],
        );

    my ($cookie_jar) = $self->read_delete_args( qw( cookie_jar ) );
    if ($cookie_jar) {
        require HTTP::Cookies::Netscape;
        $getscript_user_agent->cookie_jar(HTTP::Cookies::Netscape->new(file => $cookie_jar));
    }

    return $getscript_user_agent;
}

sub get_mapping {
    my ($self) = @_;

    my ($dataset, $csver_remote, $chr, $start, $end, $gff_source) =
        $self->read_args(qw{ dataset csver_remote chr start end gff_source });
    my $params = $self->format_params({
        dataset => $dataset,
        cs      => $csver_remote,
        chr     => $chr,
        start   => $start,
        end     => $end,
        'author' => $self->arg('author'),
    });
    if ($dataset and defined($csver_remote)) {
        my $mapping_xml = $self->do_http_request('GET', 'get_mapping', $params);
        return Bio::Otter::Mapping->new_from_xml($mapping_xml);
    }
    else {
        return Bio::Otter::Mapping::_equiv_new(-chr => $chr); 
    }
}

# FIXME: duplication with B:O:L:Client->_do_http_request()
#
sub do_http_request {
    my ($self, $method, $scriptname, $params) = @_;

    my $context = $self->log_context;

    # create a user agent to send the request
    # (side-effect: require's HTTP::Request on first use)
    #
    my $ua = $self->user_agent;

    my $request = HTTP::Request->new;
    $request->method($method);

    #$request->accept_decodable(HTTP::Message::Decodable);

    # FIXME: params if POST
    my $url = $self->url_root . '/' . $scriptname;

    if ($method eq 'GET') {
        $url = $url . ($params ? "?$params" : '');
    }
    elsif ($method eq 'POST') {
        $request->content($params);
    }
    else {
        die "method '$method' is not supported";
    }
    $self->log_message("http: URL: $url");

    $request->uri($url);

    # do the request
    my $response;
    $self->time_diff_for(
        'http', sub {
            $response = $ua->request($request);
            die "No response for $context\n" unless $response;
            $self->log_message(
                sprintf("http: bytes: %d (decoded), %d (raw)  status: %s",
                        length($response->decoded_content),
                        length($response->content),
                        $response->status_line)
                );
        });

    if ($response->is_success) {
        if ($response->content_type =~ m{^application/json($|;)}) { # charset ignored
            return $self->_json_content($response)
        }
        else {
            my $xml = $response->decoded_content;
            my ($content) = $xml =~ m{<otter[^\>]*\>\s*(.*)</otter>}s;
            return $content ? $content : $xml;
        }
    }
    else {

        my $res = $response->content;
        $self->log_chunk('http: error', $res);

        my $err_msg;

        ## no critic ( RegularExpressions::ProhibitComplexRegexes )
        if (my ($err) = $res =~ /ERROR:[[:space:]]*(.+)/s) {
            $err =~ s/\A(^-+[[:blank:]]*EXCEPTION[[:blank:]]*-+\n)+//m; # remove boring initial lines
            $err =~ s/\n.*//s; # keep only the first line
            $err_msg = $err;
        }
        elsif ($res =~ /The Sanger Institute Web service you requested is temporarily unavailable/) {
            my $code = $response->code;
            my $message = $response->message;
            $err_msg = "This Sanger web service is temporarily unavailable: status = ${code} ${message}";
        }
        else {
            $err_msg = $res;
        }

        die "Webserver error for $context: $err_msg\n";
    }
}

sub _json_content {
    my ($self, $response) = @_;
    require JSON;
    return JSON->new->decode($response->decoded_content);
}

sub url_root {
    my ($self) = @_;
    return $getscript_url_root if $getscript_url_root;

    ($getscript_url_root) = $self->read_delete_args( qw( url_root ) );
    return $getscript_url_root;
}

# Primarily for the benefit of tests
sub DESTROY {
    undef $me;

    undef $getscript_session_dir;
    undef $getscript_local_db;
    undef $getscript_log4perl_level;
    undef $getscript_user_agent;
    undef $getscript_url_root;

    $getscript_log_context = 'not-set';
    %getscript_args = ();

    return;
}

1;
