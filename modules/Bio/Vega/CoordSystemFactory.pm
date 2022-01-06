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

package Bio::Vega::CoordSystemFactory;

use strict;
use warnings;

use Carp;
use Readonly;

use Bio::EnsEMBL::CoordSystem;

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

    if ($self->dba) {
        my $cs = $self->_dba_cs($name);
        return $self->_cached_cs($name, $cs);
    }
    elsif ($self->_cached_cs($name)) {
        my $cs = $self->_local_cs($name, $self->_cached_cs($name));
        return $self->_cached_cs($name, $cs);
    }
    else {
        my $cs = $self->_local_cs($name);
        return $self->_cached_cs($name, $cs);
    }
}

sub known {
  my ($self) = @_;

  my $_coord_system_specs = $self->_coord_system_specs;
  my @sorted_array = sort { $_coord_system_specs->{$a}->{'-rank'} <=> $_coord_system_specs->{$b}->{'-rank'} } keys %$_coord_system_specs;
  if (! exists $_coord_system_specs->{$sorted_array[-1]}->{'-sequence_level'}){
      if (! exists $_coord_system_specs->{$sorted_array[-1]}->{'-default'}){
          my $cs = pop(@sorted_array);
          unshift(@sorted_array, $cs);
      }
      else {
            croak "Last element not seq_level but default version";
      }
  }
  return @sorted_array;

}

sub instantiate_all {
    my ($self) = @_;
    foreach my $name ( $self->known ) {
        # Ensure it's brought into existence and cached
        $self->coord_system($name);
    }
    return;
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
    my ($self, $name, $cs_factory) = @_;

    if ($cs_factory) {
        my $cs = Bio::EnsEMBL::CoordSystem->new('-name' => $name, %$cs_factory);
        return $cs;
    }
    else {
        my $spec = $self->override_spec->{$name};
        my $cs = Bio::EnsEMBL::CoordSystem->new('-name' => $name, %$spec);
        return $cs;
    }
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
  return $self->override_spec || {};
}

1;

__END__
