=head1 LICENSE

Copyright [2018-2020] EMBL-European Bioinformatics Institute

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


### Bio::Otter::Utils::AccessionInfo

package Bio::Otter::Utils::AccessionInfo;

use strict;
use warnings;

use Readonly;

use Time::HiRes qw( gettimeofday tv_interval );
use Bio::Otter::Utils::RequireModule qw(require_module);

=pod

=head1 NAME - Bio::Otter::Utils::AccessionInfo

A cover for MM to allow an (as-yet-to-be-written) alternative driver to be substituted,
such as one which uses EBI dbfetch.

=cut

Readonly my $DEFAULT_DRIVER_CLASS => 'Bio::Otter::Utils::BulkMM';

sub new {
    my ($class, @args) = @_;

    my %options = ( driver_class => $DEFAULT_DRIVER_CLASS, @args );
    my $driver_class = delete $options{driver_class};
    require_module($driver_class);

    my $driver = $driver_class->new(%options);
    return bless { _driver => $driver }, $class;
}

sub _init {
    foreach my $method (qw( get_accession_info get_accession_info_no_sequence get_taxonomy_info db_categories debug )) {
        my $code = sub {
            my ($self, @args) = @_;
            # all calls are scalar
            my $t0 = [gettimeofday()];
            my $out = $self->{_driver}->$method(@args);
            if ($method =~ /^get/) {
                my $dt = tv_interval($t0);
                my $N = @{$args[0]};
                my $n = ref($out) eq 'HASH' ? keys %$out
                  : @$out; # get_taxonomy_info
                $N = "$n of $N" if $n != $N;
                $self->_report($method, $dt, $N);
            }
            return $out;
        };
        no strict 'refs'; ## no critic( TestingAndDebugging::ProhibitNoStrict )
        *{$method} = $code;
    }
    return;
}

sub _report {
    my ($self, $method, $dt, $many) = @_;
    my $driver_class = ref($self->{_driver});
    warn sprintf("[d] %s->%s fetched %s in %.3fs\n",
                 $driver_class, $method, $many, $dt);
    return;
}

__PACKAGE__->_init;

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

