
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
sub get_deleted_Exon_by_slice{
  my ($self, $exon,$exon_version) = @_;
  unless ($exon || $exon_version){
	 throw("no exon passed on to fetch old exon or no version supplied");
  }
  my $exon_slice=$exon->slice;
  my $exon_stable_id=$exon->stable_id;
  my $db_exon;
  my @out = grep { $_->stable_id eq $exon_stable_id and $_->version eq $exon_version }
    @{$self->SUPER::fetch_all_by_Slice_constraint($exon_slice,'e.is_current = 0 ')};
	if ($#out > 1) {
	  ##test
	  @out = sort {$a->dbID <=> $b->dbID} @out;
	  $db_exon=pop @out;
	  ##test
	  #die "\ntrying to fetch an exon for deletion there are more than one exon retrived $exon_stable_id\n";
	}
  $db_exon=$out[0];
  return $db_exon;
}

sub get_current_Exon_by_slice{
  my ($self, $exon) = @_;
  unless ($exon){
	 throw("no exon passed on to fetch old exon");
  }
  my $exon_slice=$exon->slice;
  my $exon_stable_id=$exon->stable_id;
  my @out = grep { $_->stable_id eq $exon_stable_id }
    @{ $self->fetch_all_by_Slice_constraint($exon_slice,'e.is_current = 1 ')};
	if ($#out > 1) {
	  die "trying to fetch an exon for comparison, there are more than one exon retrived for $exon_stable_id\n";
	}
  my $db_exon=$out[0];
  return $db_exon;
}

1;

__END__

=head1 NAME - Bio::Otter::DBSQL::AnnotatedExonAdaptor

=head1 AUTHOR

James Gilbert B<email> jgrg@sanger.ac.uk

