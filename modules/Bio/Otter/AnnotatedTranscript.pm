package Bio::Otter::AnnotatedTranscript;

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::Transcript;

@ISA = qw(Bio::EnsEMBL::Transcript);

sub new {
    my($class,@args) = @_;

    my $self = $class->SUPER::new(@args);

    my ($transcript_info)  = $self->_rearrange([qw(
						   INFO
						   )],@args);
    
    $self->transcript_info($transcript_info);
    
    return $self;
}


=head2 transcript_info

 Title   : transcript_info
 Usage   : $obj->transcript_info($newval)
 Function: 
 Example : 
 Returns : value of transcript_info
 Args    : newvalue (optional)


=cut

sub transcript_info {
   my ($obj,$value) = @_;

   if( defined $value) {

       if ($value->isa("Bio::Otter::TranscriptInfo")) {
	   $obj->{'transcript_info'} = $value;
           $value->transcript_stable_id($obj->stable_id);
       } else {
	   $obj->throw("Argument to transcript_info must be a Bio::Otter::TranscriptInfo object.  Currently is [$value]");
       }
    }
    return $obj->{'transcript_info'};

}

sub stable_id {
  my ($self,$arg) = @_;

  if (defined($arg)) {
     $self->SUPER::stable_id($arg);
     if (defined($self->transcript_info)) {
       $self->transcript_info->transcript_stable_id($arg)
     }
  }
  return $self->SUPER::stable_id;
}

1;
