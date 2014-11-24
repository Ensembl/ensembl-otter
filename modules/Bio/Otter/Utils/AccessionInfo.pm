
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
    foreach my $method (qw( get_accession_info get_accession_types get_taxonomy_info db_categories debug )) {
        my $code = sub {
            my ($self, @args) = @_;
            # all calls are scalar
            my $t0 = [gettimeofday()];
            my $out = $self->{_driver}->$method(@args);
            if ($method =~ /^get/) {
                my $dt = tv_interval($t0);
                my $n = @{$args[0]};
                $self->_report($method, $dt, $n);
            }
            return $out;
        };
        no strict 'refs'; ## no critic( TestingAndDebugging::ProhibitNoStrict )
        *{$method} = $code;
    }
    return;
}

sub _report {
    my ($self, $method, $dt, $count) = @_;
    my $driver_class = ref($self->{_driver});
    warn sprintf("[d] %s->%s fetched %d in %.3fs\n",
                 $driver_class, $method, $count, $dt);
    return;
}

__PACKAGE__->_init;

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

