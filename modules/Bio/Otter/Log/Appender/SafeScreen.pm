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

package Bio::Otter::Log::Appender::SafeScreen;

use warnings;
use strict;

use Data::Dumper;

use Bio::Otter::Log::Log4perl;
use base qw(Log::Log4perl::Appender);

sub new {
    my($class, @options) = @_;

    my $self = {
        name   => "unknown name",
        @options,
    };

    open(my $stdout_copy, ">&STDOUT") or die "Can't dup STDOUT";
    $self->{handle} = $stdout_copy;

    bless $self, $class;
    return $self;
}

sub log {
    my($self, %params) = @_;

    $self->{handle}->print($params{message});
    return;
}

1;

__END__

=head1 NAME

Bio::Otter::Log::Appender::SafeScreen - log to a copy of STDOUT

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

=cut

# EOF
