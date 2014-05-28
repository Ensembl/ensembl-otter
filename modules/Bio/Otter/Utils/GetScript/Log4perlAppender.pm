package Bio::Otter::Utils::GetScript::Log4perlAppender;

use warnings;
use strict;

use Bio::Otter::Utils::GetScript;

use base qw(Log::Log4perl::Appender);

sub new {
    my ($class, @options) = @_;
    return bless { @options }, $class;
}

sub log {
    my ($self, %params) = @_;
    my $msg = $params{message};
    chomp $msg;
    Bio::Otter::Utils::GetScript->log_message($msg);
    return;
}

1;
