package Bio::Otter::Utils::GetScript;

# Lightweight helper for filter_get and friends

use strict;
use warnings;

use IO::Handle;
use URI::Escape qw(uri_unescape);

# NB GetScript is a singleton...

my $me;

# ...hence these class members are simple variables.

my $context = 'not-set';
my $log_file;
my $session_dir;

my %args;

sub new {
    my ($pkg) = @_;

    die "GetScript object already instantiated" if $me;
    my $ref = "";
    $me = bless \$ref, $pkg;

    return $me;
}


sub log_context {
    my ($self, @args) = @_;
    ($context) = @args if @args;
    return $context;
}


sub parse_uri_style_args {
    my ($self) = @_;

    foreach my $pair (@ARGV) {
        my ($key, $val) = split(/=/, $pair);
        $args{uri_unescape($key)} = uri_unescape($val);
    }
    return \%args;
}

sub args {
    return \%args;
}

sub read_delete_args {
    my ($self, @wanted) = @_;
    return delete @args{@wanted};
}

sub log_arguments {
    my ($self) = @_;
    $self->log_message(sprintf "argument: %s: %s", $_, $args{$_}) for sort keys %args;
    return;
}

sub use_session_dir {
    my ($self, $sda) = @_;
    $session_dir = $sda;
    die "No session_dir argument" unless $session_dir;
    chdir($session_dir) or die "Could not chdir to '$session_dir'; $!";
    return $session_dir;
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
        , @date, $$, $context;
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

1;
