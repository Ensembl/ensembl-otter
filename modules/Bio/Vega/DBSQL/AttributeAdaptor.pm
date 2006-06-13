package Bio::Vega::DBSQL::AttributeAdaptor;

use base 'Bio::EnsEMBL::DBSQL::AttributeAdaptor';

sub store_on_ContigInfo  {
  my $self = shift;
  my $contiginfo = shift;
  my $attributes = shift;
  if(!ref($contiginfo) || !$contiginfo->isa('Bio::Vega::ContigInfo')) {
    $self->throw("ContigInfo argument expected");
  }
  if(ref($attributes) ne 'ARRAY') {
    $self->throw("Reference to list of Bio::EnsEMBL::Attribute objects argument " .
          "expected");
  }
  my $db = $self->db();
  my $dbc=$db->dbc;
  my $cia=$db->get_ContigInfoAdaptor;
  $contiginfo->adaptor($cia);
  if(!$contiginfo->is_stored($dbc)) {
    $self->throw("ContigInfo is not stored in this DB - cannot store attributes.");
  }
  my $contiginfo_id = $contiginfo->dbID();
  my $sth = $self->prepare( "INSERT into contig_attrib ".
			    "SET contig_info_id = ?, attrib_type_id = ?, ".
			    "value = ? " );

  for my $attrib ( @$attributes ) {
    if(!ref($attrib) && $attrib->isa('Bio::EnsEMBL::Attribute')) {
      $self->throw("Reference to list of Bio::EnsEMBL::Attribute objects " .
						 "argument expected.");
    }
    my $atid = $self->_store_type( $attrib );
    $sth->execute( $contiginfo_id, $atid, $attrib->value() );
  }
  return;
}

1;
__END__

=head1 NAME - Bio::Vega::DBSQL::AttributeAdaptor.pm

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk
