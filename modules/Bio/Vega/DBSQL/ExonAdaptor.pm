package Bio::Vega::DBSQL::ExonAdaptor;

use strict;
use base 'Bio::EnsEMBL::DBSQL::ExonAdaptor';
use Bio::EnsEMBL::Utils::Exception qw(throw warning);

use Bio::Vega::Exon;

    # trying to substitute the class in all possible places at once (a hack)
sub _objs_from_sth {
    my $self = shift @_;

    my $array = $self->SUPER::_objs_from_sth(@_);

    for my $exon (@$array) {
        bless $exon, 'Bio::Vega::Exon';
    }

    return $array;
}

sub update  {

  my ($self, $exon) = @_;

  if ( !$exon || !ref $exon || !$exon->isa('Bio::Vega::Exon') ) {
    throw("Must update an exon object, not a $exon");
  }

  my $sth = $self->prepare(qq{
       UPDATE exon
          SET 
              is_current = ?
        WHERE exon_id = ?
  });

  $sth->execute( $exon->is_current, $exon->dbID );
}

sub fetch_by_stable_id_version {

  my ($self, $stable_id,$version) = @_;

  my $constraint = "esi.stable_id = '$stable_id' AND esi.version = $version ORDER BY esi.modified_date DESC, esi.exon_id DESC LIMIT 1";
  my ($exon) = @{ $self->generic_fetch($constraint) };

  return $exon;
}

#sub get_deleted_Exon_by_slice {
#  my ($self, $exon, $exon_version) = @_;
#  unless ($exon || $exon_version){
#	 throw("no exon passed on to fetch old exon or no version supplied");
#  }
#
#  my $exon_stable_id=$exon->stable_id;
#  my @noncurrent_exons =    # NB: reverse order, to get the last one:
#        sort {$b->dbID <=> $a->dbID}
#        grep { $_->stable_id eq $exon_stable_id and $_->version eq $exon_version }
#        @{$self->fetch_all_by_Slice_constraint($exon->slice(), 'e.is_current = 0 ')};
#
#  return $noncurrent_exons[0];
#}
#
#sub get_current_Exon_by_slice {
#  my ($self, $exon) = @_;
#  unless ($exon){
#	 throw("no exon passed on to fetch old exon");
#  }
#
#  my $exon_stable_id=$exon->stable_id;
#  my @current_exons =
#        grep { $_->stable_id eq $exon_stable_id }
#        @{ $self->fetch_all_by_Slice_constraint($exon->slice, 'e.is_current = 1 ')};
#  if (@current_exons > 1) {
#	 die "there are ".scalar(@current_exons)." current $exon_stable_id exons in the db\n";
#  }
#  return $current_exons[0];
#}


sub fetch_latest_by_stable_id {
  my ($self, $stable_id) = @_;

  my $constraint = "esi.stable_id = '$stable_id' ORDER BY esi.modified_date DESC, esi.exon_id DESC LIMIT 1";
  my ($exon) = @{ $self->generic_fetch($constraint) };

  return $exon;
}


1;

__END__

=head1 NAME - Bio::Vega::DBSQL::ExonAdaptor

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk

