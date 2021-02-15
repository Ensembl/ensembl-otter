#!/usr/bin/env perl
# Copyright [2018-2021] EMBL-European Bioinformatics Institute
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.


use strict;
use warnings;

use lib "${ENV{ANACODE_TEAM_TOOLS}}/t/tlib";
use Test::CriticModule;

use Test::More;

use File::Slurp;
use File::Temp;
use FindBin qw($Script);
use Time::HiRes qw( gettimeofday tv_interval );

use Bio::Otter::Log::Log4perl;

my @modules;
BEGIN {
    @modules = qw(
       Bio::Otter::LogFile
       Bio::Otter::Log::Appender::SafeScreen
       Bio::Otter::Log::Layout::UseSrcTimestamp
       Bio::Otter::Log::TieHandle
       Bio::Otter::Log::WithContext
       Bio::Otter::Log::WithContextMixin
    );

    use_ok($_) foreach (@modules);
}
critic_module_ok($_) foreach (@modules);

my $fh = File::Temp->new(TEMPLATE => "${Script}.XXXXXX", TMPDIR => 1);
my $fname = $fh->filename;

my $pid = Bio::Otter::LogFile::make_log($fname, 'DEBUG');
ok($pid, 'make_log');

my $logger = Bio::Otter::Log::Log4perl->get_logger('Test.LogFile');
isa_ok($logger, 'Log::Log4perl::Logger');

ok($logger->info('Stand by for an information broadcast'), 'info');

my $timer_session = Test::LogFile::Session->new('timer');

my $n = 1000;
my $t0 = [ gettimeofday() ];
foreach my $i ( 1 .. $n ) {
    $timer_session->logger('Test.LogFile.bulk')->debug("Debug message #$i");
}
my $interval = tv_interval($t0);

my $p_dog = Test::LogFile::Session->new('dog');
my $p_cat = Test::LogFile::Session->new('cat:tom');

$logger->info('still core');
$p_cat->run;
$p_dog->run;
$logger->info('even now, still core');
$p_cat->logger('Test.LogFile.main')->error('cat error from main');

my $log = read_file($fh);
ok($log, 'slurp logfile');

like($log, qr/Test.LogFile \[-\] INFO: Stand by for an information broadcast/, 'info logged');

like($log, qr/
    \QTest.LogFile.Session [dog] DEBUG: New\E .+
    \QTest.LogFile.Session [cat..tom] DEBUG: New\E .+
    \QTest.LogFile [-] INFO: still core\E .+
    \QTest.LogFile.Session [cat..tom] DEBUG: from cat\E .+
    \QTest.LogFile.Session [dog] DEBUG: from dog\E .+
    \QTest.LogFile [-] INFO: even now, still core\E .+
    \Qmain [cat..tom] ERROR: cat error from main\E
  /sx, 'context logged');

note "Logged $n messages in $interval seconds.";

done_testing;


package Test::LogFile::Session;

sub new {
    my ($pkg, $name) = @_;
    my $self = bless { name => $name }, $pkg;
    $self->logger->debug('New');
    return $self;
}

sub logger {
    my ($self, $category) = @_;
    return Bio::Otter::Log::WithContext->get_logger($category, name => $self->name);
}

sub run {
    my ($self) = @_;
    return $self->do_debug('from ', $self->name);
}

sub do_debug {
    my ($self, @msg) = @_;
    return $self->logger->debug(@msg);
}

sub name {
    my ($self) = @_;
    return $self->{name};
}

1;

# Local Variables:
# mode: perl
# End:

# EOF
