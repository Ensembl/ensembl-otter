package Bio::Vega::CoordSystemFactory;

use strict;
use warnings;

use Carp;
use Readonly;

use Bio::EnsEMBL::CoordSystem;

# Our canned coordinate systems
#
Readonly my %_COORD_SYSTEM_SPEC => (
    'chromosome' => { '-version' => 'Otter', '-rank' => 2, '-default' => 1,                         },
    'clone'      => {                        '-rank' => 4, '-default' => 1,                         },
    'contig'     => {                        '-rank' => 5, '-default' => 1,                         },
    'dna_contig' => { '-version' => 'Otter', '-rank' => 6, '-default' => 1, '-sequence_level' => 1, },
    );

# Our canned mappings - kept here for consistency with our canned coordinate systems
#
no warnings 'qw';               ## no critic (TestingAndDebugging::ProhibitNoWarnings)
Readonly my @_MAPPINGS_SPEC => qw(
    chromosome:Otter#dna_contig:Otter
    chromosome:Otter#contig
    clone#contig
    );
use warnings 'qw';

sub new {
    my ($class, %args) = @_;
    my $self = bless { _cache => {} }, $class;

    foreach my $key ( qw( dba create_in_db override_spec ) ) {
        $self->{$key} = delete $args{$key};
    }
    if (%args) {
        croak "Unexpected args to ${class}->new: ", join(',', map { "'$_'" } keys %args);
    }
    if ($self->create_in_db and not $self->dba) {
        croak "Incompatible args to ${class}->new: 'create_in_db' requires 'dba'";
    }
    return $self;
}


# We keep a separate cache per factory, even though we could share locally-generated non-dba coord_systems
# We do not allow for multiple versions of the same coord_system

sub coord_system {
    my ($self, $name) = @_;

    my $cs = $self->_cached_cs($name);
    return $cs if $cs;

    # Not cached yet

    if ($self->dba) {
        $cs = $self->_dba_cs($name);
    } else {
        $cs = $self->_local_cs($name);
    }

    return $self->_cached_cs($name, $cs);
}

sub known {
  my ($self) = @_;

  my $_coord_system_specs = $self->_coord_system_specs;
  return sort { $_coord_system_specs->{$a}->{'-rank'} <=> $_coord_system_specs->{$b}->{'-rank'} } keys %$_coord_system_specs;
}

sub instantiate_all {
    my ($self) = @_;
    foreach my $name ( $self->known ) {
        # Ensure it's brought into existence and cached
        $self->coord_system($name);
    }
    return;
}

sub assembly_mappings {
    return @_MAPPINGS_SPEC;
}

sub _dba_cs {
    my ($self, $name) = @_;

    # Try the DB first
    my $cs_a = $self->dba->get_CoordSystemAdaptor;
    my $spec = $self->_coord_system_specs->{$name};
    my $cs   = $cs_a->fetch_by_name($name, $spec->{'-version'});
    return $cs if $cs;

    return unless $self->create_in_db;

    $cs = $self->_local_cs($name);
    $cs_a->store($cs);
    return $cs;
}

sub _local_cs {
    my ($self, $name) = @_;

    my $spec = $self->override_spec->{$name};

    my $cs = Bio::EnsEMBL::CoordSystem->new('-name' => $name, %$spec);
    return $cs;
}

# Accessors

sub dba {
    my ($self) = @_;
    my $dba = $self->{'dba'};
    return $dba;
}

sub create_in_db {
    my ($self) = @_;
    my $create_in_db = $self->{'create_in_db'};
    return $create_in_db;
}

sub override_spec {
    my ($self) = @_;
    my $override_spec = $self->{'override_spec'};
    return $override_spec;
}

sub _cache {
    my ($self) = @_;
    return $self->{'_cache'};
}

sub _cached_cs {
    my ($self, $name, @args) = @_;
    my $cache = $self->_cache;
    ($cache->{$name}) = @args if @args;
    my $_cached_cs = $cache->{$name};
    return $_cached_cs;
}

sub _coord_system_specs {
  my ($self) = @_;

  return $self->override_spec || \%_COORD_SYSTEM_SPEC;
}

1;

__END__
