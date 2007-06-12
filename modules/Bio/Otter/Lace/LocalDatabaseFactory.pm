package Bio::Otter::Lace::LocalDatabaseFactory;

use strict;
use Bio::Otter::Lace::AceDatabase;
use File::Path 'rmtree';

sub new {
    my( $pkg, $client ) = @_;

    my $self = bless {}, $pkg;
    if($client) {
        $self->Client($client);
    }
    return $self;
}

sub Client {
    my( $self, $client ) = @_;

    if ($client) {
        $self->{'_Client'} = $client;
    }
    return $self->{'_Client'};
}

############## Session recovery methods ###################################

sub list_all_current_pid {
    my $self = shift @_;

    my $current = {};

    local *PID;

    my $pipe = $^O =~ /solaris/i ? "ps -A |" : "ps ax |";
    open PID, $pipe or die "Cannot open pipe '$pipe' : $!";
    while (<PID>) {
        my ($pid) = split;
        next unless $pid =~ /^\d+$/;
        $current->{$pid} = 1;
    }
    close PID or die "Error running '$pipe' : exit $?";

    return $current;
}

sub sessions_needing_recovery {
    my $self = shift @_;

    my $existing_pid = list_all_current_pid();

    my $tmp_dir = '/var/tmp';
    local *VAR_TMP;
    opendir VAR_TMP, $tmp_dir or die "Cannot read '$tmp_dir' : $!";
    my @recovered = ();
    foreach (readdir VAR_TMP) {
        if (/^lace\.(\d+)/) {
            my $pid = $1;
            next if $existing_pid->{$pid};
            my $lace_dir = "$tmp_dir/$_";
                # Skip if directory is not ours
            my $owner = (stat($lace_dir))[4];
            next if $< != $owner;

            my $ace_wrm = "$lace_dir/database/ACEDB.wrm";
            if(-e $ace_wrm) {
                push(@recovered, $lace_dir);
            } else {
                print STDERR "\nNo such file: '$ace_wrm'\nDeleting uninitialized database '$lace_dir'\n";
                rmtree($lace_dir);
            }
        }
    }
    closedir VAR_TMP or die "Error closing directory '$tmp_dir' : $!";

    return \@recovered;
}

sub first_occurence {
    my ($self, $filename, $pattern) = @_;

    warn "Looking for a value in $filename\n";
    open ( FILE, $filename ) || die "$!";
    foreach my $line (<FILE>) {
        my ($value) = ($line =~ /$pattern/);
        if($value) {
            return $value;
        }
    }
    warn "\n\nNo value found in $filename\n\n";
}

sub make_title {
    my ($self, $adb_or_dir ) = @_ ;

    my $dir = ref($adb_or_dir) ? $adb_or_dir->home : $adb_or_dir;

    my $tail    = $self->first_occurence($dir.'/wspec/displays.wrm', qr{_DDtMain.*-t\s*"(?:lace\s+)(.*)"});
    my $species = $self->first_occurence($dir.'/rawdata/otter.ace', qr{^Species\s+"(.*)"});

    return $species.' '.$tail;
}

sub recover_session {
    my ($self, $dir) = @_;

    my $readonly_tag = $self->ace_readonly_tag();
    $readonly_tag    =~ s{(\W)}{\\$1}g;

    my $write_flag = ($dir =~ /$readonly_tag/ ? 0 : 1);

    my $adb = $self->new_AceDatabase($write_flag);
    $adb->error_flag(1);
    my $home = $adb->home;
    rename($dir, $home) or die "Cannot move '$dir' to '$home' : $!";
    my $title = "Recovered lace ". $self->make_title($adb);
    $adb->title($title);

    return $adb;
}

############## Session recovery methods end here ############################

sub ace_readonly_tag {
    my $self = shift @_;

    return '.ro';
}

sub new_AceDatabase {
    my( $self, $write_access ) = @_;

    my $adb = Bio::Otter::Lace::AceDatabase->new;
    $adb->write_access($write_access);
    $adb->Client( $self->Client() );
    my $home = $adb->home();
    my $i = ++$self->{'_last_db'};
    $adb->home("${home}_$i");
    return $adb;
}

1;

