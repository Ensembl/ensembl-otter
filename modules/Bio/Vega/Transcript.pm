package Bio::Vega::Transcript;

use strict;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use base 'Bio::EnsEMBL::Transcript';

sub new {
  my($class,@args) = @_;
  my $self = $class->SUPER::new(@args);
  my ($transcript_author,$evidence)  = rearrange([qw(AUTHOR EVIDENCE)],@args);
  $self->transcript_author($transcript_author);
  if (defined($evidence)) {
	 if (ref($evidence) eq "ARRAY") {
		$self->add_Evidence(@$evidence);
	 }
	 else {
		$self->throw(
						 "Argument to evidence must be an array ref. Currently [$evidence]"
						);
	 }
  }
  return $self;
}

sub transcript_author {
  my ($self,$value) = @_;
  if( defined $value) {
	 if ($value->isa("Bio::Vega::Author")) {
		$self->{'transcript_author'} = $value;
	 } else {
		throw("Argument to transcript_author must be a Bio::Vega::Author object.  Currently is [$value]");
	 }
  }
  return $self->{'transcript_author'};
}

sub add_Evidence {
  my ($self,$evidenceref) = @_;
  if( ! exists $self->{'evidence'} ) {
    $self->{'evidence'} = [];
  }
  foreach my $evidence ( @$evidenceref ) {
    if( ! $evidence->isa( "Bio::Vega::Evidence" )) {
		throw( "Argument to add_Evidence has to be an Bio::Vega::Evidence" );
    }
    push( @{$self->{'evidence'}}, $evidence );
  }
  return;
}

sub truncate_to_Slice {
  my( $self, $slice ) = @_;
  # start and end exon are set to zero so that we can
  # safely use them in "==" without generating warnings
  # as we loop through the list of exons.
  ### Not used until we enable translation truncating
  my $start_exon = 0;
  my $end_exon   = 0;
  my( $tsl );
  if ($tsl = $self->translation) {
	 $start_exon = $tsl->start_Exon;
	 $end_exon   = $tsl->end_Exon;
  }
  my $exons_truncated = 0;
  my $in_translation_zone = 0;
  my $slice_length = $slice->length;
  my $ex_list = $self->get_all_Exons;
  for (my $i = 0; $i < @$ex_list;) {
	 my $exon = $ex_list->[$i];
	 my $exon_start = $exon->start;
	 my $exon_end   = $exon->end;
	 if ($exon->slice != $slice or $exon_end < 1 or $exon_start > $slice_length) {
		#warn "removing exon that is off slice";
		### This won't work if get_all_Exons() ceases to return
		### a ref to the actual array of exons in the transcript.
		splice(@$ex_list, $i, 1);
		$exons_truncated++;
	 } else {
		#printf STDERR
		#    "Checking if exon %s is within slice %s of length %d\n"
		#    . "  being attached to %s and extending from %d to %d\n",
		#    $exon->stable_id, $slice, $slice_length, $exon->contig, $exon_start, $exon_end;
		$i++;
		my $trunc_flag = 0;
		if ($exon->start < 1) {
		  #warn "truncating exon that overlaps start of slice";
		  $trunc_flag = 1;
		  $exon->start(1);
		}
		if ($exon->end > $slice_length) {
		  #warn "truncating exon that overlaps end of slice";
		  $trunc_flag = 1;
		  $exon->end($slice_length);
		}
		$exons_truncated++ if $trunc_flag;
	 }
  }
  ### Hack until we fiddle with translation stuff
  if ($exons_truncated) {
	 $self->{'translation'}     = undef;
	 $self->{'_translation_id'} = undef;
  }
  return $exons_truncated;
}

sub get_Evidence {
  my $self = shift;
  if ( ! exists $self->{'evidence' } ) {
    if (!$self->adaptor() ) {
      return [];
    }

    my $ta = $self->adaptor->db->get_TranscriptAdaptor();
    $self->{'evidence'} = $ta->fetch_evidence($self);
  }
  return $self->{'evidence'};
}

sub hashkey_sub {

  my $self = shift;
  my $remarks = $self->get_all_Attributes('remark');
  my $hidden_remarks = $self->get_all_Attributes('hidden_remark');
  my $evidence=$self->get_Evidence;
  my $hashkey_sub={};
  if (defined $remarks) {
	 foreach my $rem (@$remarks){
		$hashkey_sub->{$rem->value}='remark';
	 }
  }
  if (defined $hidden_remarks) {
	 foreach my $rem (@$hidden_remarks){
		$hashkey_sub->{$rem->value}='hidden_remark';
	 }
  }
  if (defined $evidence) {
	 foreach my $evi (@$evidence){
		my $e=$evi->name.$evi->type;
		$hashkey_sub->{$e}='evidence';
	 }
  }
  my $exons=$self->get_all_Exons;

  foreach my $exon (@$exons){
	 $hashkey_sub->{$exon->stable_id}='exon_stable_id';
  }
  return $hashkey_sub;

}


sub hashkey {

  my $self=shift;
  my $slice      = $self->{'slice'};
  my $slice_name = ($slice) ? $slice->name() : undef;
  my $start      = $self->{'start'};
  my $end        = $self->{'end'};
  my $strand     = $self->{'strand'};
  my $biotype    = $self->{'biotype'};
  my $status     = $self->{'status'};
  my $exons      = $self->get_all_Exons;
  my $exon_count = @$exons;
  my $description = $self->{'description'} ? $self->{'description'}: '' ;
  my $attribs     = $self->get_all_Attributes;
  my $attrib_count = @$attribs ;
  my $transcript_name = $self->get_all_Attributes('name') ;
  my $mRNA_start_NF = $self->get_all_Attributes('mRNA_start_NF') ;
  my $mRNA_end_NF = $self->get_all_Attributes('mRNA_end_NF') ;
  my $cds_start_NF = $self->get_all_Attributes('cds_start_NF') ;
  my $cds_end_NF = $self->get_all_Attributes('cds_end_NF') ;
  my $evidence= $self->get_Evidence;
  my $evidence_count=0;
  
  ##should transcript_class_name be added??
  if (defined $evidence) {
	 $evidence_count= scalar(@$evidence);
  }

  my ($msNF,$meNF,$csNF,$ceNF,$tn);

  if (defined $mRNA_start_NF){
	 if (@$mRNA_start_NF > 1){
		throw("Transcript has more than one value for mRNA_start_NF attrib cannot generate correct hashkey");
	 }
	 $msNF=$mRNA_start_NF->[0]->value;
  }
  else {
	 $msNF='';
  }
  if (defined $mRNA_end_NF){
	 if (@$mRNA_end_NF > 1){
		throw("Transcript has more than one value for mRNA_end_NF attrib cannot generate correct hashkey");
	 }
	 $meNF=$mRNA_end_NF->[0]->value;
  }
  else {
	 $meNF='';
  }
  if (defined $cds_start_NF){
	 if (@$cds_start_NF > 1){
		throw("Transcript has more than one value for cds_start_NF attrib cannot generate correct hashkey");
	 }
	 $csNF=$cds_start_NF->[0]->value;
  }
  else {
	 $csNF='';
  }
  if (defined $cds_end_NF){
	 if (@$cds_end_NF > 1){
		throw("Transcript has more than one value for cds_end_NF attrib cannot generate correct hashkey");
	 }
	 $ceNF=$cds_end_NF->[0]->value;
  }
  else {
	 $ceNF='';
  }
  if (defined $transcript_name) {
	 if (@$transcript_name > 1){
		throw("Transcript has more than one value for transcript name attrib cannot generate correct hashkey");
	 }
	 $tn=$transcript_name->[0]->value;
  }

  unless($slice_name) {
    throw('Slice must be set to generate correct hashkey.');
  }

  unless($start) {
    warning("start attribute must be defined to generate correct hashkey.");
  }

  unless($end) {
    throw("end attribute must be defined to generate correct hashkey.");
  }

  unless($strand) {
    throw("strand attribute must be defined to generate correct hashkey.");
  }

  unless($biotype) {
    throw("biotype attribute must be defined to generate correct hashkey.");
  }

  unless($status) {
    throw("status attribute must be defined to generate correct hashkey.");
  }

  unless($exon_count > 0) {
    throw("there are no exons for this transcript to generate correct hashkey");
  }

  unless($transcript_name) {
    throw('transcript name must be defined to generate correct hashkey.');
  }

  my $hashkey_main="$slice_name-$start-$end-$strand-$biotype-$status-$exon_count-$tn-$msNF-$meNF-$csNF-$ceNF-$description-$evidence_count-$attrib_count";

  return ($hashkey_main);
}

1;

__END__

=head1 NAME - Bio::Vega::Transcript

=head1 AUTHOR

Sindhu Pillai B<email> sp1@sanger.ac.uk
