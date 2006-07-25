package Bio::Vega::DBSQL::TranscriptAdaptor;

use strict;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Vega::Transcript;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);

use base 'Bio::EnsEMBL::DBSQL::TranscriptAdaptor';

sub fetch_by_stable_id  {

  my ($self, $stable_id) = @_;
  my ($transcript) = $self->SUPER::fetch_by_stable_id($stable_id);
  if ($transcript){
	 bless $transcript, "Bio::Vega::Transcript";
  }
  return $transcript;

}
sub fetch_by_stable_id_version  {

  my ($self, $stable_id,$version) = @_;

  my $constraint = "tsi.stable_id = '$stable_id' AND tsi.version = $version";
  my ($transcript) = @{ $self->generic_fetch($constraint) };

  return $transcript;

}
sub store_Evidence {

  my ($self,$transcript_id,$evidence_list) = @_;
  unless ($evidence_list || $transcript_id) {
	 throw("evidence object list :$evidence_list and transcript_id:$transcript_id must be entered to store an evidence");
  }
  # Insert new evidence
  my $sth = $self->prepare(q{
        INSERT INTO evidence(transcript_id, name,type) VALUES (?,?,?)
        });

  foreach my $evidence (@$evidence_list) {
	 my $name=$evidence->name;
	 my $type=$evidence->type;
	 $sth->execute($transcript_id,$name,$type);
  }
}

1;

	





