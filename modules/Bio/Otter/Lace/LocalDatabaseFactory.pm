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
    my( $self ) = @_;
    
    my $proc_table = Proc::ProcessTable->new;
    my @otterlace_procs = grep {$_->cmndline =~ /otterlace/} @{$proc_table->table};
    my %existing_pid = map {$_->pid, 1} @otterlace_procs;

    my $tmp_dir = '/var/tmp';
    opendir my $var_tmp, $tmp_dir or die "Cannot read '$tmp_dir' : $!";
    my $to_recover = [];
    my $version = $self->Client->version;
    foreach (readdir $var_tmp) {
        if (/^lace_$version\.(\d+)/o) {
            my $pid = $1;
            next if $existing_pid{$pid};
            my $lace_dir = "$tmp_dir/$_";

            # Skip if directory is not ours
            my ($owner, $mtime) = (stat($lace_dir))[4,9];
            next if $< != $owner;

            my $ace_wrm = "$lace_dir/database/ACEDB.wrm";
            if (-e $ace_wrm) {
                my $title = $self->get_title($lace_dir);
                push(@$to_recover, [$lace_dir, $mtime, $title]);
            } else {
                my $client = $self->Client;
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
    }
    closedir $var_tmp or die "Error reading directory '$tmp_dir' : $!";

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

    my $adb = $self->new_AceDatabase($write_flag);
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
    
    my $dataset = $adb->smart_slice->DataSet;
    
    $dataset->session_dir($adb->home);
    
    my $gff_filters = $dataset->parse_gff_filters;
    
    $dataset->reload_gff_filter_state($gff_filters);
    
    $adb->make_pipeline_DataFactory;
    $adb->get_filter_loaded_states_from_acedb;

    my $title = $self->get_title($adb->home);
    unless ($title =~ /^Recovered/) {
        $title = "Recovered $title";
    }
    $adb->title($title);

    return ($adb, $gff_filters);
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
    
    my $version = $self->Client->version;
    my $readonly_tag = $write_access ? '' : '.ro';
    my $i = ++$self->{'_last_db'};  # Could just use a class variable,
                                    # then we wouldn't have to make sure that
                                    # we only create one LocalDatabaseFactory
    return "/var/tmp/lace_${version}.${$}${readonly_tag}.$i";
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk


