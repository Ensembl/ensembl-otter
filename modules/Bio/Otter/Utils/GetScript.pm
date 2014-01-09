package Bio::Otter::Utils::GetScript;

# Lightweight helper for filter_get and friends

use strict;
use warnings;

use IO::Handle;
use Time::HiRes qw(time);
use URI::Escape qw(uri_unescape);

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

# Deferred until needed on cache miss
#
sub do_requires {
    require DBI;
    require Bio::Otter::Lace::DB;
    require Bio::Otter::Lace::DB::ColumnAdaptor;
    return;
}

# NB GetScript is a singleton...

my $me;

# ...hence these class members are simple variables.

my $getscript_log_context = 'not-set';
my $getscript_session_dir;
my $getscript_local_db;

my %getscript_args;

sub new {
    my ($pkg) = @_;

    die "GetScript object already instantiated" if $me;
    my $ref = "";
    $me = bless \$ref, $pkg;

    return $me;
}

sub log_context {
    my ($self, @args) = @_;
    ($getscript_log_context) = @args if @args;
    return $getscript_log_context;
}

sub parse_uri_style_args {
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

sub read_delete_args {
    my ($self, @wanted) = @_;
    return delete @getscript_args{@wanted};
}

sub log_arguments {
    my ($self) = @_;
    $self->log_message(sprintf "argument: %s: %s", $_, $getscript_args{$_}) for sort keys %getscript_args;
    return;
}

sub use_session_dir {
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

    sub open_log {
        my ($self, $log_path) = @_;
        open $log_file, '>>', $log_path
            or die "failed to open the log file '${log_path}'";
        $log_file->autoflush(1);
        return $log_file;
    }

    # Not a method
    sub _log_prefix {
        my @t = localtime;
        my @date = ( 1900+$t[5], $t[4]+1, @t[3,2,1,0] );
        return sprintf "%4d-%02d-%02d %02d:%02d:%02d: %6d: %-35s "
            , @date, $$, $getscript_log_context;
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

    return $getscript_local_db = Bio::Otter::Lace::DB->new($getscript_session_dir);
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
            my $rv = $db_filter_adaptor->update_for_filter_get
              ($column_name, # WHERE: name
               $cache_file, # SET: gff_file, status = 'Loading'
               $process_gff || 0); # SET: process_gff flag
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

1;
