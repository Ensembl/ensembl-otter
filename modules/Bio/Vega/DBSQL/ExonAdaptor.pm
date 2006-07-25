
package Bio::Vega::DBSQL::ExonAdaptor;

use strict;
use base 'Bio::EnsEMBL::DBSQL::ExonAdaptor';
use Bio::EnsEMBL::Utils::Exception qw(throw warning);

sub update  {

  my ($self, $exon) = @_;
  my $update = 0;

  if ( !defined $exon || !ref $exon || !$exon->isa('Bio::EnsEMBL::Exon') ) {
    throw("Must update an exon object, not a $exon");
  }

  my $update_exon_sql = qq(
       UPDATE exon
          SET 
              is_current = ?
        WHERE exon_id = ?
  );


  my $sth = $self->prepare( $update_exon_sql );
  $sth->bind_param(1, $exon->is_current);

  $sth->bind_param(2, $exon->dbID);

  $sth->execute();

}

sub fetch_by_stable_id_version  {

  my ($self, $stable_id,$version) = @_;

  my $constraint = "esi.stable_id = '$stable_id' AND esi.version = $version";
  my ($exon) = @{ $self->generic_fetch($constraint) };

  return $exon;

}
1;

__END__

=head1 NAME - Bio::Otter::DBSQL::AnnotatedExonAdaptor

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

