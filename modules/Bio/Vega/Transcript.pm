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

#sub translation  {

 # my $self = shift;
  #if( @_ ) {
   # my $value = shift;
    #if( defined($value) &&
     #   (!ref($value) || !$value->isa('Bio::Vega::Translation'))) {
      #throw("Bio::Vega::Translation argument expected.");
    #}
    #$self->{'translation'} = $value;
 # } elsif( !exists($self->{'translation'}) and defined($self->adaptor())) {
  #  $self->{'translation'} =
   #   $self->adaptor()->db()->get_TranslationAdaptor()->
    #    fetch_by_Transcript( $self );
  #}
  #return $self->{'translation'};

#}

sub get_Evidence {
  my $self = shift;
  return $self->{'evidence'};
}

sub hashkey_sub {

  my $self = shift;
  my $remarks = $self->get_all_Attributes('remark');
  my $hidden_remarks = $self->get_all_Attributes('hidden_remark');
  my $hashkey_sub={};
  if (defined $remarks) {
	 foreach my $rem (@$remarks){
		$hashkey_sub->{$rem->value}=1;
	 }
  }
  if (defined $hidden_remarks) {
	 foreach my $rem (@$hidden_remarks){
		$hashkey_sub->{$rem->value}=1;
	 }
  }
  my $exons=$self->get_all_Exons;

  foreach my $exon (@$exons){
	 $hashkey_sub->{$exon->stable_id}=1;
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

  my $hashkey_main="$slice_name-$start-$end-$strand-$biotype-$status-$exon_count-$tn-$msNF-$meNF-$csNF-$ceNF-$attrib_count-$description";

  return ($hashkey_main);
}

1;

__END__

=head1 NAME - Bio::Vega::Transcript

=head1 AUTHOR

Sindhu Pillai B<email> sp1@sanger.ac.uk
