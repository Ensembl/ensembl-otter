package Bio::Vega::DBSQL::TranscriptAdaptor;

use strict;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Vega::Transcript;
use Bio::Vega::Evidence;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);

use base 'Bio::EnsEMBL::DBSQL::TranscriptAdaptor';

sub fetch_by_stable_id  {
  my ($self, $stable_id) = @_;
  my ($transcript) = $self->SUPER::fetch_by_stable_id($stable_id);
  if ($transcript){
	 $self->reincarnate_transcript($transcript);
  }
  return $transcript;
}

sub reincarnate_transcript{
  my ($self,$transcript) = @_;
  bless $transcript, "Bio::Vega::Transcript";
  $self->fetch_transcript_author($transcript);
  return $transcript;
}

sub fetch_by_stable_id_version  {
  my ($self, $stable_id,$version) = @_;
  my $constraint = "tsi.stable_id = '$stable_id' AND tsi.version = $version";
  my ($transcript) = @{ $self->generic_fetch($constraint) };
  if ($transcript){
	 $self->reincarnate_transcript($transcript);
  }
  return $transcript;
}

sub fetch_all_by_Slice  {
  my ($self,$slice,$load_exons,$logic_name)  = @_;
  my ($transcripts) = $self->SUPER::fetch_all_by_Slice($slice,$load_exons,$logic_name);
  if ($transcripts){
	 foreach my $transcript(@$transcripts){
		$self->reincarnate_transcript($transcript);
	 }
  }
  return $transcripts;
}
sub fetch_all_by_Gene  {
  my ($self,$gene)  = @_;
  my ($transcripts) = $self->SUPER::fetch_all_by_Gene($gene);
  if ($transcripts){
	 foreach my $transcript(@$transcripts){
		$self->reincarnate_transcript($transcript);
	 }
  }
  return $transcripts;
}

sub fetch_evidence {
  my ($self,$transcript)=@_;
  if( !ref($transcript) || !$transcript->isa('Bio::EnsEMBL::Transcript') ) {
    throw('Transcript argument is required.');
  }
  my $tid = $transcript->dbID();
  if(!defined($tid)) {
    throw("Transcript must have dbID.");
  }
  my $sth = $self->prepare("SELECT name,type " .
                           "FROM evidence " .
                           "WHERE transcript_id = ? ");
  $sth->execute($tid);
  my $results;
  while  (my $ref = $sth->fetchrow_hashref) {
	 my $obj=Bio::Vega::Evidence->new;
	 $obj->name($ref->{name});
	 $obj->type($ref->{type});
	 push @$results,$obj;
  }
  $sth->finish();
  return $results;
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

sub fetch_transcript_author {
  my ($self,$transcript)=@_;
  my $authad = $self->db->get_AuthorAdaptor;
  my $author= $authad->fetch_transcript_author($transcript->dbID);
  $transcript->transcript_author($author);
  return $transcript;
}

sub get_deleted_Transcript_by_slice{
  my ($self, $transcript,$tran_version) = @_;
  unless ($transcript || $tran_version){
	 throw("no transcript passed on to fetch old transcript or no version supplied");
  }
  my $tran_slice=$transcript->slice;
  my $tran_stable_id=$transcript->stable_id;
  my $db_tran;
  my @out = grep { $_->stable_id eq $tran_stable_id and $_->version eq $tran_version }
    @{$self->SUPER::fetch_all_by_Slice_constraint($tran_slice,'t.is_current = 0 ')};
  if ($#out > 1) {
	 ##test
	 @out = sort {$a->dbID <=> $b->dbID} @out;
	 $db_tran=pop @out;
	 ##test
	 #die "there are more than one transcript retrived\n".$db_tran->dbID;
  }
  else {
	 $db_tran=$out[0];
  }

  if ($db_tran){
	 $self->reincarnate_transcript($db_tran);
  }
  return $db_tran;
}

sub get_current_Transcript_by_slice{
  my ($self, $transcript) = @_;
  unless ($transcript){
	 throw("no transcript passed on to fetch old transcript");
  }
  my $tran_slice=$transcript->slice;
  my $tran_stable_id=$transcript->stable_id;
  my @out = grep { $_->stable_id eq $tran_stable_id }
    @{ $self->fetch_all_by_Slice_constraint($tran_slice,'t.is_current = 1 ')};
	if ($#out > 1) {
	  die "there are more than one transcript retrived\n";
	}
  my $db_tran=$out[0];
  if ($db_tran){
	 $self->reincarnate_transcript($db_tran);
  }
  return $db_tran;
}

1;

	





