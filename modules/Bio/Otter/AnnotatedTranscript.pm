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



## This method removes all exons from this transcript which lie outside the slice. 
## Exons overlapping the start and end are truncated and the $exon->start / end coordinates 
## and also $transcript->start/end are adjusted accordingly 
sub truncate_to_Slice{
    my ($self , $slice ) = @_ ;
   
    warn "doing truncate to slice bit!!!!" ;
    my $is_truncated    = 0;
    my $exon_list       = $self->get_all_Exons;
    
    my $translation     = undef;
    unless($translation = $self->translation ){
        print STDERR "no translation for " . $self->transcript_info->name ."\n" ;   
        if ( ($$exon_list[0]->start < 1) || ($$exon_list[$#$exon_list]->end) > $slice->length ){
            $is_truncated = 1;
        }
        return $is_truncated ;
    } 
    
    my $coding_region_start    = $self->coding_region_start ;
    my $coding_region_end      = $self->coding_region_end ;
    
    my $original_start_exon = $translation->start_Exon; 
    my $original_end_exon = $translation->end_Exon ;
    
    my $original_translation_end = $translation->end ; 
    $translation->{'end'} = undef;
    
    $self->{'coding_region_start'} = undef ;
    $self->{'coding_region_end' } = undef ;
    
    my $strand = $$exon_list[0]->strand ;

    if ( $coding_region_start > $slice->length  ||  $coding_region_end < 1 ){
        # remove transcript if the entire transcript lies outside the slice
         $self->{'translation'} = undef;
         $self->{'_translation_id'} = undef;
    } 

    #   for each exon ( working in a 5' to 3 ' direction)
    #       if exon lies outside slice, remove it
    #       else
    #           if exon lies outside the coding region
    #               ignore and move onto next
    #           else (some part of) the exon lies in the coding region    
    #               if the start exon has NOT been set already
    #                   if we have a translation (it doesnt lie outside the slice coords)
    #                       the first exon we come to should be set as the start exon (we go in a 5' to 3' direction)   
    #                       adjust translation->start and exon->start/end depending on wheather exon is overlapping slice 
    #               if start is set (it should be by now)
    #                   set this to the end exon 
    #                   adjust $translation->end  and exon->start/end depending on wheather exon is overlapping slice     
    
    my ($start_removed, $end_removed) ;
    my $five_prime_is_set  ;
    for (my $i = 0 ; $i < @$exon_list ;){
        my $exon = @$exon_list[$i] ;
        my $exon_start = $exon->start ;
        my $exon_end = $exon->end ;
        my $strand = $exon->strand;
; 

        if ($exon_start > $slice->length || $exon->end < 1 ){
            # exon lies before/after slice ends - should be removed 
            splice(@$exon_list, $i, 1);
            $is_truncated = 1;  
            if ($exon == $original_start_exon){
                $start_removed = 1
            }elsif ($exon == $original_end_exon &&  $strand == -1 ){
                $end_removed = 1 ;
            }   
        }
        else{   #all other exons that lie (partially) inside the slice
            $i++;
            if ( !($exon_end < $coding_region_start  || $exon_start > $coding_region_end))  {   
                # ignore UTR exons. At least part of this exon lies within the coding region. 
                # Exon list is in a 5' to 3' direction, so first exon here should be set as start (other exons removed by previous part)
                                
                if ( ! $five_prime_is_set ){   
                    if ($self->_translation_id ){
                        # this must be our five prime exon - translation isnt removed (so part of translation lies in slice)
                        # and exon exon is within coding region. Calculate start                    
                        $translation->start_Exon($exon);
                        $five_prime_is_set = 1;
                        
                        if ($strand == 1 ){

                            #check if this is our original start exon we are truncating#
                            if ( $exon == $original_start_exon){
                                if ($exon->start < 1){
                                    # truncate and sort coords
                                    my $difference = 1 - $exon->start;
                                    $exon->start(1);
                                    my $new_start = $translation->start - $difference ;
                                    $new_start = 1 if ($new_start < 1) ;
                                    $translation->start($new_start) ;
                                    $is_truncated = 1;
                                    $self->_reset_start_phase($exon, $difference) ;
                                }#else{# this is our original start exon, but hasnt been truncated - leave translation->start as it is! }                      
                            }else{
                                # this is not the original start exon , the original start must have been removed already
                                if ( ($exon->start <  1 )){ 
                                    my $difference = 1 - $exon->start ;
                                    $exon->start(1);
                                    $self->_reset_start_phase($exon, $difference) ;                                
                                }
                                $translation->start(1);
                                $is_truncated = 1 ;
                            }
                            
                        }else{ # strand must be negative!                      

                            if($exon == $original_start_exon){ # first coding (-ve) exon overlapping end of slice 
                                
                                if ($exon->end > $slice->length){
                                    #this is our original end exon , truncate and sort the coords if (part of it) lies outside the slice
                                    my $difference = $slice->length - $exon->end;    
                                    $exon->end($slice->length) ;
                                    my $new_start = $translation->start - $difference;
                                    $new_start = $slice->length if  ($new_start > $slice->length) ;
                                    $translation->start($new_start);
                                    $is_truncated = 1 ;
                                    $self->_reset_end_phase($exon , $difference) ;
                                }
                                #else{ ## this is the original start exon, but hasnt been truncated - leave start as it is }     
                            }
                            else{ # this is not the original start exon 
                                if ($exon->end > $slice->length){
                                    my $difference = $slice->length - $exon->end ;
                                    $exon->end($slice->length) ;
                                    $self->_reset_end_phase($exon , $difference) ;
                                }
                                $translation->start(1);
                                $is_truncated = 1;
                            }
                        }
                    } ## end of if (translation_id)
                         
                } ## end if($five_prime_is_set){  } ....
                
                ### SET END EXON in theis half of the for loop. Set it to every exon (we go in the 5' to 3 ' direction). 
                if ( $five_prime_is_set){      # start has been set                     
                    if ($self->{'_translation_id'}){
                        $translation->end_Exon($exon) ; #set end exon to this one
                        if ($strand == 1){

                            if ($exon == $original_end_exon){
                                ## may need to truncate it!
                                $translation->end($original_translation_end);
                                if ($exon->end > $slice->length){
                                    my $difference = $$exon->end - $slice->length ;
                                    $exon->end($slice->length);                                    
                                    my $new_end = $original_translation_end - $difference; 
                                    $new_end = 1 if ($new_end < 1) ;
                                    $translation->end($new_end);
                                    $is_truncated = 1 ;
                                    
                                    $self->_reset_end_phase($exon, $difference);
                                }else{
                                    # this is the original end exon, and it has not been truncated - set $translation->end to original value
                                    $translation->end ($original_translation_end);
                                    
                                }
                            }else{
                                #this is not the original end exon set end to end of exon
                                if ($exon->end > $slice->length) {
                                    my $difference = $slice->length - $exon->end ;
                                    $exon->end($slice->length);
                                    $self->_reset_end_phase($exon, $difference);
                                }
                                my $exon_length = $exon->end - $exon->start ;
                                $translation->end($exon_length);
                                # if this is the last exon in our list ;
                                if ($i == scalar(@$exon_list)){ ## we already incremented $i - so dont need to subtract 1 from size of exon list
                                    $is_truncated = 1
                                }                       
                            }
                        
                        }else{ ## strand is -ve

                            if ($exon == $original_end_exon){
                                # may need to truncate it and  fiddle with coords 
                                if ($exon->start < 1){
                                    my $difference = 1 - $exon->start;
                                    $exon->start(1) ;
                                    my $new_end = $original_translation_end - $difference ;
                                    $new_end = 1 if ($new_end < 1) ; 
                                    $translation->end($new_end) ;
                                    $is_truncated = 1 ;
                                    $self->_reset_start_phase($exon , $difference);
                                }else{
                                    ## put it back to the original value - as this remains the same as before
                                    $translation->end($original_translation_end) ;
                                }
                            }else{
                                if ( $exon->start < 1 ){
                                    my $difference = 1 - $exon->start ;
                                    $exon->start(1);
                                    $self->_reset_start_phase($exon , $difference);
                                }
                                my $exon_length = $exon->end - $exon->start;
                                $translation->end( $exon_length); 
                                # if this is the last exon in our list ; 
                                if ($i == scalar(@$exon_list) ){ ## remember that we did the increment on $i before anything else $i 
                                    $is_truncated = 1
                                }
                            }
                        }
                    }                
                }         
            }
        }
    } 
    
    
    #set these to undef, otherwise this  method returns cached values, calculated from the first time it was called. 
    $self->{'coding_region_end'} = undef ;
    $self->{'coding_region_start'} = undef ;
        
    return $is_truncated;
}


sub _reset_start_phase{
    my ($self , $exon , $difference ) = @_ ;       
    my $new_phase = ($exon->phase + $difference) % 3 ;
    warn ">>>>resetting start - old : " . $exon->phase ."  new : $new_phase "  .$self->transcript_info->name ;
    
    $exon->phase($new_phase) ;
}


sub _reset_end_phase {
    my ($self , $exon , $difference) = @_ ;
    my $new_phase = ($exon->end_phase - $difference) % 3 ;
    $exon->phase($new_phase) ;
    
    warn ">>>>restting end" ; 
}




1;
