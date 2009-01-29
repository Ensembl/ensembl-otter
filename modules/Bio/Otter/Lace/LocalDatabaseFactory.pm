package Bio::Otter::Lace::LocalDatabaseFactory;

use strict;
use warnings;
use Carp;
use Bio::Otter::Lace::AceDatabase;
use File::Path 'rmtree';
use Proc::ProcessTable;


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

sub sessions_needing_recovery {
    my $self = shift @_;
    
    my $proc_table = Proc::ProcessTable->new;
    my %existing_pid = map {$_->pid, 1} @{$proc_table->table};

    my $tmp_dir = '/var/tmp';
    local *VAR_TMP;
    opendir VAR_TMP, $tmp_dir or die "Cannot read '$tmp_dir' : $!";
    my $to_recover = [];
    foreach (readdir VAR_TMP) {
        if (/^lace\.(\d+)/) {
            my $pid = $1;
            next if $existing_pid{$pid};
            my $lace_dir = "$tmp_dir/$_";
                # Skip if directory is not ours
            my $owner = (stat($lace_dir))[4];
            next if $< != $owner;

            my $ace_wrm = "$lace_dir/database/ACEDB.wrm";
            if (-e $ace_wrm) {
                push(@$to_recover, $lace_dir);
            } else {
                print STDERR "\nNo such file: '$ace_wrm'\nDeleting uninitialized database '$lace_dir'\n";
                rmtree($lace_dir);
            }
        }
    }
    closedir VAR_TMP or die "Error reading directory '$tmp_dir' : $!";

    return $to_recover;
}

sub first_occurence {
    my ($self, $filename, $pattern) = @_;

    # warn "Looking for a value in $filename\n";
    open ( my $fh, $filename ) or die "Can't read file '$filename'; $!";
    foreach my $line (<$fh>) {
        my ($value) = ($line =~ /$pattern/);
        if($value) {
            return $value;
        }
    }
    close $fh;
    warn "\n\nNo value for '$pattern' found in $filename\n\n";
}

sub make_title {
    my ($self, $adb_or_dir ) = @_ ;

    my $dir = ref($adb_or_dir) ? $adb_or_dir->home : $adb_or_dir;

    my $tail    = $self->first_occurence($dir.'/wspec/displays.wrm', qr{_DDtMain.*-t\s*"(?:lace\s+)(.*)"});
    my $species = $self->first_occurence($dir.'/rawdata/otter.ace', qr{^Species\s+"(.*)"});

    return "$species $tail";
}

sub recover_session {
    my ($self, $dir) = @_;

    $self->kill_old_sgifaceserver($dir);

    my $write_flag = $dir =~ /\.ro/ ? 0 : 1;

    my $adb = $self->new_AceDatabase($write_flag);
    $adb->error_flag(1);
    my $home = $adb->home;
    rename($dir, $home) or die "Cannot move '$dir' to '$home'; $!";
    my $title = "Recovered lace ". $self->make_title($adb);
    $adb->title($title);

    return $adb;
}

sub kill_old_sgifaceserver {
    my ($self, $dir) = @_;
    
    # Kill any sgifaceservers from crashed otterlace 
    my $proc_list = Proc::ProcessTable->new;
    foreach my $proc (@{$proc_list->table}) {
        my ($cmnd, @args) = split /\s+/, $proc->cmndline;
        next unless $cmnd eq 'sgifaceserver';
        next unless $args[0] eq $dir;
        printf STDERR "Killing old sgifaceserver '%s'\n", $proc->cmndline;
        kill 9, $proc->pid;
    }    
}

############## Session recovery methods end here ############################

sub new_AceDatabase {
    my( $self, $write_access ) = @_;

    my $adb = Bio::Otter::Lace::AceDatabase->new;
    $adb->write_access($write_access);
    $adb->Client( $self->Client() );
    $adb->home($self->make_home_path($write_access));
    return $adb;
}

sub make_home_path {
    my ($self, $write_access) = @_;
    
    my $readonly_tag = $write_access ? '' : '.ro';
    my $i = ++$self->{'_last_db'};
    return "/var/tmp/lace.${$}${readonly_tag}_$i";
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


