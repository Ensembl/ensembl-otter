package Bio::Otter::Lace::LocalDatabaseFactory;

use strict;
use warnings;
use Carp;

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
    my( $self ) = @_;
    
    my $proc_table = Proc::ProcessTable->new;
    my @otterlace_procs = grep {$_->cmndline =~ /otterlace/} @{$proc_table->table};
    my %existing_pid = map {$_->pid, 1} @otterlace_procs;

    my $to_recover = [];
    my $client = $self->Client;

    foreach ( $client->all_sessions ) {
        my ( $lace_dir, $pid, $mtime ) = @{$_};
        next if $existing_pid{$pid};

        my $ace_wrm = "$lace_dir/database/ACEDB.wrm";
        if (-e $ace_wrm) {
            my $title = $self->get_title($lace_dir);
            push(@$to_recover, [$lace_dir, $mtime, $title]);
        } else {
            my $save_sub = $client->fatal_error_prompt;
            $client->fatal_error_prompt(sub{ die shift });
            eval {
                # Attempt to release locks of uninitialised sessions
                my $adb = $self->recover_session($lace_dir);
                $adb->error_flag(0);    # It is uninitialised, so we want it to be removed
                $lace_dir = $adb->home;
                if ($adb->write_access) {
                    $adb->unlock_otter_slice;
                    print STDERR "\nRemoved lock from uninitialised database in '$lace_dir'\n";
                }
            };
            $client->fatal_error_prompt($save_sub);
            if (-d $lace_dir) {
                # Belt and braces - if the session was unrecoverable we want it to be deleted.
                print STDERR "\nNo such file: '$lace_dir/database/ACEDB.wrm'\nDeleting uninitialized database '$lace_dir'\n";
                rmtree($lace_dir);
            }
        }
    }

    # Sort by modification date, ascending
    $to_recover = [sort {$a->[1] <=> $b->[1]} @$to_recover];
    
    return $to_recover;
}

sub get_title {
    my ($self, $home_dir) = @_;
    
    my $displays_file = "$home_dir/wspec/displays.wrm";
    open my $DISP, '<', $displays_file or die "Can't read '$displays_file'; $!";
    my $title;
    while (<$DISP>) {
        if (/_DDtMain.*-t\s*"([^"]+)/) {
            $title = $1;
            last;
        }
    }
    close $DISP or die "Error reading '$displays_file'; $!";
    
    if ($title) {
        return $title;
    } else {
        die "Failed to fetch title from '$displays_file'";        
    }
}

sub recover_session {
    my ($self, $dir) = @_;
    
    $self->kill_old_sgifaceserver($dir);

    my $write_flag = $dir =~ /\.ro/ ? 0 : 1;

    my $adb = $self->Client->new_AceDatabase($write_flag);
    $adb->error_flag(1);
    my $home = $adb->home;
    rename($dir, $home) or die "Cannot move '$dir' to '$home'; $!";
    
    unless ($adb->db_initialized) {
        eval { $adb->recover_smart_slice_from_region_xml_file };
        warn $@ if $@;
        return $adb;
    }

    # All the info we need about the genomic region
    # in the lace database is saved in the region XML
    # dot file.
    $adb->recover_smart_slice_from_region_xml_file;
    $adb->reload_filter_state;

    my $title = $self->get_title($adb->home);
    unless ($title =~ /^Recovered/) {
        $title = "Recovered $title";
    }
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

    return;
}

############## Session recovery methods end here ############################

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


