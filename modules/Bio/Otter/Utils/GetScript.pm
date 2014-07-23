package Bio::Otter::Utils::GetScript;

# Lightweight helper for filter_get and friends

use strict;
use warnings;

use IO::Handle;
use Scalar::Util qw(weaken);
use Time::HiRes qw( time gettimeofday );
use URI::Escape  qw(uri_unescape);

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
#
sub do_requires {
    require DBI;
    require Bio::Otter::Lace::DB;
    require Bio::Otter::Lace::DB::ColumnAdaptor;
    return;
}

# Override in child if necessary.
#
sub log_context  { return shift->require_arg('gff_source'); }

# NB GetScript is a singleton...

my $me;

# ...hence these class members are simple variables.

my $getscript_log_context = 'not-set';
my $getscript_session_dir;
my $getscript_local_db;
my $getscript_log4perl_level;

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

    $self->show_version if exists $args->{'--version'}; # exits
    die "failing as required" if $args->{'fail'};       # test case

    $self->_use_session_dir($self->read_delete_args('session_dir'));

    $self->_set_log_context($self->log_context);
    $self->_open_log($self->log_filename);

    if ($getscript_log4perl_level) {
        require Log::Log4perl;
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
    die "No argument '$key'" unless exists $getscript_args{$key};
    return $getscript_args{$key};
}

sub arg {
    my ($self, $key) = @_;
    return $getscript_args{$key};
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

    $self->log_message("$log: start");

    my $start_time = time;
    $code->();
    my $end_time = time;

    my $time = sprintf "time (sec): %.3f", $end_time - $start_time;
    $self->log_message("$log: finish: $time");

    return;
}

sub local_db {
    my ($self) = @_;

    return $getscript_local_db if $getscript_local_db;

    return $getscript_local_db = Bio::Otter::Lace::DB->new(home => $getscript_session_dir);
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
            my $msg = "Update of otter_filter table in SQLite db failed; $err";
            $self->log_message($msg);
            die $msg;
        }
        $dbh->disconnect;
    } );
    return;
}

# Primarily for the benefit of tests
sub DESTROY {
    undef $me;

    undef $getscript_session_dir;
    undef $getscript_local_db;
    undef $getscript_log4perl_level;

    $getscript_log_context = 'not-set';
    %getscript_args = ();

    return;
}

1;
