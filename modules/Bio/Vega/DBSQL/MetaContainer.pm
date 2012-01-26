package Bio::Vega::DBSQL::MetaContainer;

use strict;
use warnings;

use base 'Bio::EnsEMBL::DBSQL::MetaContainer';


=head2 get_primary_prefix

  Arg [1]    : none
  Example    : $prefix = $meta_container->get_primary_prefix();
  Description: Retrieves the primary prefix for this database from the
               meta container
  Returntype : string
  Exceptions : none
  Caller     : ?

=cut

sub get_primary_prefix {
  my ($self) = @_;

  my $sth = $self->db->dbc->prepare( "SELECT meta_value
                             FROM meta
                             WHERE meta_key = 'prefix.primary'" );
  $sth->execute;

  if( my $arrRef = $sth->fetchrow_arrayref() ) {
    return $arrRef->[0];
  } else {
    return;
  }
}

=head2 get_species_prefix

  Arg [1]    : none
  Example    : $prefix = $meta_container->get_species_prefix();
  Description: Retrieves the species prefix for this database from the
               meta container
  Returntype : string
  Exceptions : none
  Caller     : ?

=cut

sub get_species_prefix {
  my ($self) = @_;

  my $sth = $self->db->dbc->prepare( "SELECT meta_value
                             FROM meta
                             WHERE meta_key = 'prefix.species'" );
  $sth->execute;

  if( my $arrRef = $sth->fetchrow_arrayref() ) {
    return $arrRef->[0];
  } else {
    return;
  }
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

