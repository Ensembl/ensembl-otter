=head1 LICENSE

Copyright [2018-2019] EMBL-European Bioinformatics Institute

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


package Bio::Vega::DBSQL::AttributeAdaptor;

use strict;
use warnings;

use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use base 'Bio::EnsEMBL::DBSQL::AttributeAdaptor';

sub fetch_all_by_ContigInfo  {

  my ($self, $ci) = @_;

  if(!ref($ci) || !$ci->isa('Bio::Vega::ContigInfo')) {
    throw('ContigInfo argument is required.');
  }

  my $ciid = $ci->dbID();

  if(!defined($ciid)) {
    throw("ContigInfo must have dbID.");
  }
  my $sth = $self->prepare("SELECT at.code, at.name, at.description, " .
                           "       cia.value " .
                           "FROM contig_attrib cia, attrib_type at " .
                           "WHERE cia.contig_info_id = ? " .
                           "AND   at.attrib_type_id = cia.attrib_type_id");

  $sth->execute($ciid);

  my $results = $self->_obj_from_sth($sth);

  $sth->finish();

  return $results;

}

sub _store_type {

    # override superclass method to fill in missing names for Attributes

    my ($self, $attrib) = @_;

    unless ($attrib->name) {
        my $sth = $self->prepare(qq{
SELECT name 
FROM   attrib_type 
WHERE  code = ?
});
        $sth->execute($attrib->code);
        my ($name) = $sth->fetchrow_array;

        die "Failed to find attribute name for code: ".$attrib->code unless $name;

        $attrib->name($name);
    }

    return $self->SUPER::_store_type($attrib);
}


sub store_on_ContigInfo  {
  my ($self, $contiginfo, $attributes) = @_;
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
  my $sth = $self->prepare(q{
      INSERT into contig_attrib (contig_info_id, attrib_type_id, value)
                         VALUES (?,              ?,              ?)
      });

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

Ana Code B<email> anacode@sanger.ac.uk

