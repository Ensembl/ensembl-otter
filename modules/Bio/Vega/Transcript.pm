package Bio::Vega::Transcript;

use strict;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );

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
  my ($obj,$value) = @_;
  if( defined $value) {
	 if ($value->isa("Bio::Vega::Author")) {
		$obj->{'transcript_author'} = $value;
	 } else {
		$obj->throw("Argument to transcript_author must be a Bio::Vega::Author object.  Currently is [$value]");
	 }
  }
  return $obj->{'transcript_author'};
}

sub add_Evidence {
  my ($self,$evidenceref) = @_;
  if( ! exists $self->{'evidence'} ) {
    $self->{'evidence'} = [];
  }
  foreach my $evidence ( @$evidenceref ) {
    if( ! $evidence->isa( "Bio::Vega::Evidence" )) {
		$self->throw( "Argument to add_Evidence has to be an Bio::Vega::Evidence" );
    }
    push( @{$self->{'evidence'}}, $evidence );
  }
  return;
}

1;

__END__

=head1 NAME - Bio::Vega::Transcript

=head1 AUTHOR

Sindhu Pillai B<email> sp1@sanger.ac.uk
