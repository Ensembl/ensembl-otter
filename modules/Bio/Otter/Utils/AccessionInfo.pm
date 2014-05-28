
### Bio::Otter::Utils::AccessionInfo

package Bio::Otter::Utils::AccessionInfo;

use strict;
use warnings;

use Readonly;

use Bio::Otter::Utils::RequireModule qw(require_module);

=pod

=head1 NAME - Bio::Otter::Utils::AccessionInfo

A cover for MM to allow an (as-yet-to-be-written) alternative driver to be substituted,
such as one which uses EBI dbfetch.

=cut

Readonly my $DEFAULT_DRIVER_CLASS => 'Bio::Otter::Utils::MM';

sub new {
    my ($class, @args) = @_;

    my %options = ( driver_class => $DEFAULT_DRIVER_CLASS, @args );
    my $driver_class = delete $options{driver_class};
    require_module($driver_class);

    my $driver = $driver_class->new(%options);
    return bless { _driver => $driver }, $class;
}

sub get_accession_info  { my ($self, @args) = @_; return $self->{_driver}->get_accession_info(@args);  }
sub get_accession_types { my ($self, @args) = @_; return $self->{_driver}->get_accession_types(@args); }
sub get_taxonomy_info   { my ($self, @args) = @_; return $self->{_driver}->get_taxonomy_info(@args);   }
sub db_categories       { my ($self, @args) = @_; return $self->{_driver}->db_categories(@args);       }
sub debug               { my ($self, @args) = @_; return $self->{_driver}->debug(@args);               }

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

