=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

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

package Bio::Otter::Utils::Cleanup;
use strict;
use warnings;

use File::Path qw{ remove_tree };
use POSIX ();
use Try::Tiny;

use Bio::Otter::Log::Log4perl 'logger';
use Bio::Otter::Lace::Client;
use MenuCanvasWindow::SessionWindow;


our $DELETE_AFTER_DAYS = 14; # Delete sessions, logfiles older than /days

sub new {
    my ($class, $client) = @_;
    my $self = bless { client => $client }, $class;
    return $self;
}

sub client {
    my ($self) = @_;
    return $self->{client};
}

sub clean {
    my ($self) = @_;
    $self->cleanup_log_dir('otter');
    $self->cleanup_sessions;
    $self->cleanup_zmap_configs;
    return;
}

sub fork_and_clean {
    my ($self, $delay) = @_;
    my $pid = fork();
    if (!defined $pid) {
        die "fork failed: $!";
    } elsif ($pid) {
        # parent - nothing else to do
        return;
    } else {
        # child
        try {
            $0 = 'otter_cleanup';
            sleep $delay;
            $self->clean;
            $self->logger->info("Cleanup finished, pid $$\n");
            close STDERR; # _exit does not flush
            close STDOUT;
        }; # no catch, just be sure to _exit
        POSIX::_exit(0); # avoid triggering DESTROY
        return; # quieten perlcritic
    }
}


sub cleanup_log_dir {
    my ($self, $file_root, $days) = @_;
    $days ||= $DELETE_AFTER_DAYS;
    $file_root ||= 'client';

    my $log_dir = $self->client->get_log_dir or return;
    my @logs = grep { /^$file_root\..*\.log$/ } $self->_read_dir($log_dir);
    foreach my $leaf (sort @logs) {
        my $full = "$log_dir/$leaf";
        next unless (-M $full > $days);
        if (unlink $full) {
            $self->logger->info("Deleted old logfile '$full'");
        } else {
            $self->logger->warn("Couldn't delete file '$full' : $!");
        }
    }
    return;
}

sub cleanup_sessions {
    my ($self) = @_;

    foreach my $dir (sort $self->client->all_session_dirs('*')) {
        next unless $dir =~ /\.done$/;
        my $age = int(-M $dir);
        next unless $age > $DELETE_AFTER_DAYS;

        if (remove_tree($dir)) {
            $self->logger->info("cleanup_sessions removed $dir, $age days old");
        } else {
            $self->logger->error("cleanup_sessions FAILED to remove $dir, $age days old");
        }
    }

    return;
}

sub cleanup_zmap_configs {
    my ($self) = @_;
    foreach my $zconfsdir ( MenuCanvasWindow::SessionWindow->zmap_configs_dirs ) {
        next unless -d $zconfsdir;
        foreach my $leaf (sort $self->_read_dir($zconfsdir)) {
            my $dir = "$zconfsdir/$leaf";
            my $age = int(-M $dir);
            my $zlog = "$dir/zmap.log";
            $age = int(-M $zlog) if -f $zlog; # probably a bit newer
            next unless $age > $DELETE_AFTER_DAYS;

            if (remove_tree($dir)) {
                $self->logger->info("cleanup_zmap_configs removed $dir, $age days old");
            } else {
                $self->logger->error("cleanup_zmap_configs FAILED to remove $dir, $age days old");
            }
        }
    }
    return;
}


sub _read_dir { # want File::Slurp
    my ($self, $dir) = @_;
    opendir my $DH, $dir
      or $self->logger->logconfess("Can't open directory '$dir': $!");
    my @out = grep { $_ !~ /^\.\.?$/ } readdir $DH;
    closedir $DH
      or $self->logger->logconfess("Error after readdir '$dir' : $!");
    die unless wantarray;
    return @out;
}


1;
