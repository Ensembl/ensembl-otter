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

sub truncate_to_Slice {
    my( $self, $slice ) = @_;
    
    my $start_exon = 0;
    my $end_exon   = 0;
    my( $tsl );
    if ($tsl = $self->translation) {
        $start_exon = $tsl->start_Exon;
        $end_exon   = $tsl->end_Exon;
    }
    
    my $is_truncated = 0;
    my $in_translation_zone = 0;
    my $slice_length = $slice->length;
    my $ex_list = $self->get_all_Exons;
    for (my $i = 0; $i < @$ex_list;) {
        my $exon = $ex_list->[$i];
        my $exon_start = $exon->start;
        my $exon_end   = $exon->end;
        if ($exon->contig != $slice or $exon_end < 1 or $exon_start > $slice_length) {
            #warn "removing exon that is off slice";
            ### This won't work if get_all_Exons() ceases to return
            ### a ref to the actual array of exons in the transcript.
            splice(@$ex_list, $i, 1);
            $is_truncated = 1;
        } else {
            $i++;
            if ($exon->start < 1) {
                #warn "truncating exon that overlaps start of slice";
                $is_truncated = 1;
                $exon->start(1);
            }
            if ($exon->end > $slice_length) {
                #warn "truncating exon that overlaps end of slice";
                $is_truncated = 1;
                $exon->end($slice_length);
            }
        }
    }
    
    ### Hack until we fiddle with translation stuff
    if ($is_truncated) {
        $self->{'translation'}     = undef
        $self->{'_translation_id'} = undef;
    }
    
    return $is_truncated;
}

1;
