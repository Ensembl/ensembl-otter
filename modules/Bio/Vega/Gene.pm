package Bio::Vega::Gene;

use strict;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );

use base 'Bio::EnsEMBL::Gene';


sub new {
  my($class,@args) = @_;
  my $self = $class->SUPER::new(@args);
  my ($gene_author)  = rearrange([qw(AUTHOR)],@args);
  $self->gene_author($gene_author);
  return $self;
}

sub gene_author {
  my ($self,$value) = @_;
  if( defined $value) {
	 if ($value->isa("Bio::Vega::Author")) {
		$self->{'gene_author'} = $value;
	 } else {
		$self->throw("Argument to gene_author must be a Bio::Vega::Author object.  Currently is [$value]");
	 }
  }
  return $self->{'gene_author'};
}

sub source  {

  my $self = shift;
  $self->{'source'} = shift if( @_ );
  return ( $self->{'source'} || "havana" );

}

sub hashkey_sub {

  my $self = shift;
  my $hashkey_sub={};
  my $remarks = $self->get_all_Attributes('remark');
  if (defined $remarks) {
	 foreach my $rem (@$remarks){
		$hashkey_sub->{$rem->value}=1;
	 }
  }
  my $hidden_remarks = $self->get_all_Attributes('hidden_remark');
  if (defined $hidden_remarks) {
	 foreach my $rem (@$hidden_remarks){
		$hashkey_sub->{$rem->value}=1;
	 }
  }
  my $synonyms = $self->get_all_Attributes('synonym');
  if (defined $synonyms) {
	 foreach my $syn (@$synonyms){
		$hashkey_sub->{$syn->value}=1;
	 }
  }
  my $trans=$self->get_all_Transcripts;
  foreach my $tran (@$trans){
	 $hashkey_sub->{$tran->stable_id}=1;
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
  my $source     = $self->{'source'};
  my $trans      = $self->get_all_Transcripts;
  my $tran_count = @$trans;
  my $description = $self->{'description'} ? $self->{'description'}: '' ;
  my $attribs     = $self->get_all_Attributes;
  my $attrib_count = @$attribs ;
  my $gene_name = $self->get_all_Attributes('name') ;

  my $gn;

  if (defined $gene_name) {
	 if (@$gene_name > 1){
		throw("Gene has more than one value for gene name attrib cannot generate correct hashkey");
	 }
	 $gn=$gene_name->[0]->value;
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

  unless($source) {
    throw("source attribute must be defined to generate correct hashkey.");
  }

  unless($tran_count > 0) {
    throw("there are no transcripts for this gene to generate correct hashkey");
  }

  unless($gene_name) {
    throw('gene name must be defined to generate correct hashkey.');
  }

  my $hashkey_main="$slice_name-$start-$end-$strand-$biotype-$status-$source-$tran_count-$gn-$attrib_count-$description";

  return ($hashkey_main);
}



=head2 truncated_flag

Either TRUE or FALSE (1 or 0), it flags whether
the gene contains all its components that are
stored in the database, and hence whether it is
editable in the client.  Defaults to 0.

=cut

sub truncated_flag {
  my( $self, $flag ) = @_;
  if (defined $flag) {
	 $self->{'truncated_flag'} = $flag ? 1 : 0;
  }
  return $self->{'truncated_flag'} || 0;
}


1;

__END__

=head1 NAME - Bio::Vega::Gene

=head1 AUTHOR

Sindhu Pillai B<email> sp1@sanger.ac.uk
