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



## This method removes all exons from this transcript which lie outside the slice. 
## Exons overlapping the start and end are truncated and the $exon->start / end coordinates 
## and also $transcript->start/end are adjusted accordingly
sub Colin_truncate_to_Slice{
    my ($self , $slice ) = @_ ;
    
    my $name = $self->transcript_info->name ;

    # print STDERR "name : $name" ;

    my $is_truncated    = 0;
    my $exon_list       = $self->get_all_Exons;
    
    my $transcript_info = $self->transcript_info; 
    my $translation     = undef;
    
    unless($translation = $self->translation ){
        print STDERR "no translation for " . $self->transcript_info->name ."\n" ;   
        if ($$exon_list[0]->strand == 1 && ( ($$exon_list[0]->start < 1) || ($$exon_list[$#$exon_list]->end > $slice->length )) ){
            $is_truncated = 1;
        }
        elsif($$exon_list[0]->strand == -1 && ( $$exon_list[$#$exon_list]->end < 1) || ( $$exon_list[0]->end > $slice->length) ){
            $is_truncated = 1; 
        }
    } 
   
    my ($coding_region_start , $coding_region_end , $original_start_exon ,  $original_end_exon , $original_translation_start , $original_translation_end  ) ;
    if (defined $translation){
        $coding_region_start    = $self->coding_region_start ;
        $coding_region_end      = $self->coding_region_end ;

        $original_start_exon = $translation->start_Exon || 0 ; # the 0 should stop errors getting printed 
        $original_end_exon = $translation->end_Exon || 0;

        $original_translation_start = $translation->start ;
        $translation->{'start'} = undef ;
        
        $original_translation_end = $translation->end ; 
        $translation->{'end'} = undef;

        $self->{'coding_region_start'} = undef ;
        $self->{'coding_region_end' } = undef ;

    }
    my $original_cds_end_exon =  $exon_list->[$#$exon_list] ;  
    
    my $strand = $exon_list->[0]->strand ;

    if (defined $translation && ( $coding_region_start > $slice->length  ||  $coding_region_end < 1 )){
        # remove transcript if the entire transcript lies outside the slice
         $self->{'translation'} = undef;
         $self->{'_translation_id'} = undef;

    } 

    #   for each exon ( working in a 5' to 3 ' direction)
    #       if exon lies outside slice, remove it
    #       else
    #           if exon lies outside the coding region
    #               UTR exon - truncate if needed 
    #           else (some part of) the exon lies in the coding region    
    #               if the start exon has NOT been set already
    #                   if we have a translation (it doesnt lie outside the slice coords)
    #                       the first exon we come to should be set as the start exon (we go in a 5' to 3' direction)   
    #                       adjust translation->start and exon->start/end depending on wheather exon is overlapping slice 
    #               if start is set (it should be by now)
    #                   set this to the end exon 
    #                   adjust $translation->end  and exon->start/end depending on wheather exon is overlapping slice     



    # do this first - not as efficient, but otherwise it will make the next bit really difficult- having exons in the sequence that are not in the correct order
    $self->_remove_exons_from_other_Assemblies($exon_list , $slice);
    
    
    my ($start_removed, $end_removed) ;
    my $five_prime_is_set  ;
    for (my $i = 0 ; $i < @$exon_list ;){
        my $exon = $exon_list->[$i] ;
        my $exon_start = $exon->start ;

        my $exon_end = $exon->end  ;

        if ( $exon->end < 1 or $exon_start > $slice->length) {
            # current exon is on a different contig or  lies before/after slice ends - should be removed 
            $self->_exon_completely_outside_slice($exon_list , $i , $original_start_exon , $original_end_exon) ;            
            $is_truncated = 1;      
        }
        else{   #current exon lies (partially) inside the slice
            $i++;
            if ( ( !defined $translation) || $exon_end < $coding_region_start  || $exon_start > $coding_region_end)  {    
                # these must be UTR exons (or a non coding transcript). if start and end overlap slice , truncate them 
                $is_truncated = $self->_truncate_UTR_or_non_coding_exons($exon, $slice->length , $is_truncated) ;
            }
            else{ 
                # At least part of this exon lies within the coding region. (Non UTR exons)
                # Exon list is in a 5' to 3' direction, so first exon here should be set as start (other exons removed by previous part)
                if ( ! $five_prime_is_set ){   
                    
                    if ($self->_translation_id ){
                        # this must be our five prime exon - translation isnt removed (so part of translation lies in slice)
                        # and exon exon is within coding region. Calculate start                    
                        $translation->start_Exon($exon);
                        $five_prime_is_set = 1;
                        
                        if ($strand == 1 ){
                            $is_truncated = $self->_do_first_exon_plus_strand    ($exon, $original_start_exon, $original_end_exon, $original_translation_start, $original_translation_end, $is_truncated ) ;                         
                        }else{ # strand must be negative                    
                            $is_truncated = $self->_do_first_exon_negative_strand($exon, $original_start_exon, $original_end_exon, $original_translation_start, $original_translation_end, $is_truncated, $slice->length) ;
                        }
                    } ## end of if ($self->translation_id)
                         
                } ## end if($five_prime_is_set)                
                
                ### SET END EXON in this half of the for loop. Set it to every exon (we go in the 5' to 3 ' direction). 
                if ( $five_prime_is_set){      # start has been set                     
                    
                    if ($translation) {
                        
                        $translation->end_Exon($exon) ; #set end exon to this one
                        if ($strand == 1){
                            $self->_do_last_exon_plus_strand($exon, $original_start_exon, $original_end_exon, $original_translation_start, $original_translation_end, $is_truncated,  $slice->length) ;                       
                        }else{ ## strand is -ve
                            $self->_do_last_exon_negative_strand($exon, $original_start_exon, $original_end_exon, $original_translation_start, $original_translation_end, $is_truncated, $original_translation_end ) ;
                        }
                    }                
                }         
            }
        }
    }  
    
    ## set cds/mRNA_not_found for the end exons
    if ( $exon_list->[$#$exon_list] !=  $original_cds_end_exon){       
        $self->transcript_info->cds_end_not_found(1);
    }
    if (defined($translation) && $original_end_exon != $translation->end_Exon){
        $self->transcript_info->mRNA_end_not_found(1) ;
    }

    ##### we may have removed all but UTR exons! - shouldnt have a translation
    
    if (defined($translation) && (!defined $translation->start_Exon || ! defined $translation->end_Exon ) ){
        $self->{'translation'} = undef;
        $self->{'_translation_id'} = undef;
    #    warn "only UTR exons for " . $self->transcript_info->name ; 
    }    
    
    #set these to undef, otherwise this  method returns cached values, calculated from the first time it was called. 
    $self->{'coding_region_end'} = undef ;
    $self->{'coding_region_start'} = undef ;
        
    return $is_truncated;
}



# removes exons that are not on this Assembly
sub _remove_exons_from_other_Assemblies{
    my ($self , $exon_list , $slice) = @_ ;

    for (my $i = 0 ; $i < @$exon_list ;) {
        my $exon = $exon_list->[$i] ;
        if ($exon->contig != $slice ){
            splice(@$exon_list ,$i , 1) 
        }else{
            $i ++ ;
        }
    }
}

## removes exons that are completley outiside the slice coordinates
sub _exon_completely_outside_slice{
    my ($self , $exon_list , $i , $original_start_exon , $original_end_exon) =@_ ;
   
    my $exon = $exon_list->[$i] ;
#    my $strand = $exon->strand ; 
    
    ## set the appropriate values in transcript_info if necessary.
    my $transcript_info = $self->transcript_info ;
    # if it if the first exon - set start no found
    if ($i == 0){
        $transcript_info->cds_start_not_found(1);
    }
    # or the last exon set end not found
    if($i ==  scalar(@$exon_list) - 1  ){
        $transcript_info->cds_end_not_found(1);
    } 
        
    if ($exon == $original_start_exon){
        $transcript_info->mRNA_start_not_found(1) ;
    }
    if ($exon == $original_end_exon){
        $transcript_info->mRNA_end_not_found(1) ;
    }   
    
    #remove the exon
    splice(@$exon_list, $i, 1);
}

## exons that are passed to this routine are UTR exons that may need truncated. 
sub _truncate_UTR_or_non_coding_exons{
    my ($self , $exon , $slice_length , $is_truncated ) =@_ ;
    
    if ($exon->start < 1){
        $exon->start(1) ;
        $self->transcript_info->cds_start_not_found(1);
        $is_truncated = 1 ;
    }
    if ($exon->end > $slice_length){
        $exon->end($slice_length) ;
        $self->transcript_info->cds_end_not_found(1) ;
        $is_truncated = 1;
    }  
    return $is_truncated ;
}



# the next four methods truncate the exon (if necessary) and set the values affected by the change
# each is slightly different and depends on the strand and position of the exon.
sub _do_first_exon_plus_strand{
    my ($self, $exon, $original_start_exon, $original_end_exon, $original_translation_start , $original_translation_end, $is_truncated   ) = @_ ;
    
    if ($exon == $original_start_exon) {
        if ($exon->start < 1){
            $self->_chop_exon_start($exon , $original_start_exon , $original_end_exon , $original_translation_start , $original_translation_end  ) ;         
            $self->transcript_info->mRNA_start_not_found(1) ;
            $self->transcript_info->cds_start_not_found(1) ;
            $is_truncated = 1 ;
        }else { 
            #this our original start exon - but hasnt been truncated , dont do anything to it 
            $self->translation->start($original_translation_start) ;
        }
    
    }else{
        # this is not the original start exon , the original start must have been removed already
        if ( ($exon->start <  1 )){ 
            $self->_chop_exon_start($exon, $original_start_exon , $original_end_exon , $original_translation_start , $original_translation_end ) ;                                
        }
        $self->translation->start(1);
        $is_truncated = 1 ;
        $self->transcript_info->mRNA_start_not_found(1) ;
        $self->transcript_info->cds_start_not_found(1) ;
    }         
    return $is_truncated   
}


sub _do_first_exon_negative_strand{
    my ($self, $exon, $original_start_exon , $original_end_exon  ,  $original_translation_start , $original_translation_end ,  $is_truncated ,  $slice_length ) = @_ ;
       
    if ($exon == $original_start_exon){
        if ($exon->end > $slice_length){          
            my $difference = $self->_chop_exon_end($exon , $original_start_exon , $original_end_exon , $original_translation_start , $original_translation_end , $slice_length);            
            my $new_start = $self->translation->start - $difference ;
            if ($new_start < 1 ) {
                $new_start =  1 ;    
                $self->transcript_info->cds_start_not_found(1) ;
            }
            $self->translation->start($new_start);  
            $is_truncated = 1 ;
            $self->transcript_info->mRNA_start_not_found(1) ;
        }
        else{
            #original start exon - but not getting truncated - leave it as it is}
            $self->translation->start($original_translation_start);
        }
    }
    else{ # not the original start exon
        if ($exon->end > $slice_length){
            $self->_chop_exon_end($exon, $original_start_exon , $original_end_exon ,$original_translation_start , $original_translation_end  , $slice_length);
        }
        $self->translation->start(1) ;
        $is_truncated = 1 ;
        $self->transcript_info->mRNA_start_not_found(1) ;
        $self->transcript_info->cds_start_not_found(1) ;
    }
    return $is_truncated ; 
}

# every exon (after the mRNA start exon) is set to translation->end_Exon, this truncates +ve stranded ones if necessary  
sub _do_last_exon_plus_strand{
    my ($self, $exon , $original_start_exon, $original_end_exon, $original_translation_start, $original_translation_end, $is_truncated, $slice_length) = @_ ;
    
    my $exon_length = $exon->end - $exon->start + 1 ;
    
    if ($exon ==  $original_end_exon) {
        my $new_end = $original_translation_end ;
        if ($exon->end > $slice_length){
            $self->_chop_exon_end($exon , $original_start_exon , $original_end_exon ,$original_translation_start , $original_translation_end, $slice_length) ;
            if ($original_translation_end > $exon_length){
                $new_end = $exon_length ;
#                $self->transcript_info(1) ;
            }
            $is_truncated = 1 ;
        }        
        else{   # this is our original exon and has not been truncated 
            return if $original_end_exon == $self->translation->start_Exon ; # otherwise we get problems where start is the same as end
            $self->translation->end($new_end) ;
        }
    }else{
        ## not the original end exon    
        if ($exon->end > $slice_length){
            $self->_chop_exon_end($exon, $original_start_exon , $original_end_exon , $original_translation_start , $original_translation_end , $slice_length) ;
            $is_truncated = 1 ;
        }
        my $exon_length = $exon->end - $exon->start ;
        $self->translation->end($exon_length) ;  # remember that we must be in the CDS to reach here - it will get set back if 
    }
    return $is_truncated ;
}



# every exon (after the mRNA start exon) is set to translation->end_Exon, this truncates -ve stranded ones if necessary
sub _do_last_exon_negative_strand{
    my ($self, $exon , $original_start_exon, $original_end_exon , $original_translation_start , $original_translation_end , $is_truncated ) = @_ ;
    
    if ($exon == $original_end_exon){
        return if ($original_end_exon == $self->translation->start_Exon) ; # otherwise we have problems where start and end exon are the same
        if ($exon->start < 1){
            $self->_chop_exon_start($exon , $original_start_exon , $original_end_exon , $original_translation_start , $original_translation_end ) ;            
            $is_truncated = 1 ;
        }else{
            # else this is our original end exon, but hasnt been trunctaed                
            $self->translation->end($original_translation_end) ;
        } 
    }else{ # this is not the original end exon 
        if ($exon->start < 1) {
            $self->_chop_exon_start($exon , $original_start_exon , $original_end_exon , $original_translation_start , $original_translation_end ) ;    
        }
        my $exon_length = $exon->end - $exon->start + 1 ;
        $self->translation->end($exon_length)  ;
        $is_truncated =  1 ;
#        $self->transcript_info->mRNA_end_not_found(1) ;
#        $self->transcript_info->cds_end_not_found(1) ;
    }
    return $is_truncated ;
}

 
## chop_exon_start deals with setting the new $exon->start and $translation-Start values now the exon is being truncated
sub _chop_exon_start{
    my ($self , $exon , $original_start_exon , $original_end_exon , $original_translation_start , $original_translation_end ) = @_ ;

    my $difference =    2 - $exon->start      ;
    $exon->start(1) ;
    if ($exon->strand == 1){    
        $self->_reset_start_phase($exon, $difference);    
        # check here if we have the original-start exon - adjust translation start if needed 
        
        if ($exon == $original_start_exon){
            my $new_start = $original_translation_start - $difference ;
            if ( $new_start < 1 ){
                $new_start = 1;
                $self->transcript_info->mRNA_start_not_found(1) ;
            }      
            $self->translation->start($new_start) ;        
            $self->transcript_info->cds_start_not_found(1) ;
        }
        
        if ($exon == $original_end_exon ){
            my $new_end = $original_translation_end - $difference ;
            if ($difference > $original_translation_end   ){
                $self->translation->{'start'} = undef ;
                $self->translation->{'end'} = undef ;
                $self->transcript_info->mRNA_start_not_found(1) ;
                $self->transcript_info->cds_start_not_found(1);
            } 
        }       
    }
    
    else{ ## -ve strand
        $self->_reset_end_phase($exon, $difference);
        # check if we have the original end exon
        if ($exon == $original_end_exon){
            my $exon_length = $exon->end - $exon->start + 1;
            my $new_end = $original_translation_end ;
            if ( $original_translation_end > $exon_length) {
                $new_end = $exon_length ;
                $self->transcript_info->mRNA_end_not_found(1) ;
            } 
            $self->translation->end($new_end) ;
            $self-> transcript_info->cds_end_not_found(1) ;
        }
    }
    return $difference;
}

## chop_exon_end deals with setting the new $exon->end and $translation->end values now the exon is being truncated
sub _chop_exon_end{
    my ($self , $exon , $original_start_exon , $original_end_exon , $original_translation_start , $original_translation_end ,   $slice_length) = @_ ;
    
    my $translation = $self->translation ;
    my $difference =  $exon->end - $slice_length  ;
    $exon->end($slice_length) ;
    my $exon_length = $exon->end - $exon->start + 1;
    
    if ($exon->strand == 1){
    
        $self->_reset_end_phase($exon, $difference);    
        if ($exon == $original_start_exon){
            if ($original_translation_start > $exon_length){
                ## starts after the slice end - no transaltion    
                $translation->{'start'} = undef ;
                $translation->{'end'} = undef ;
            }
            else{
                ## (part of) translation still inside  
                $translation->start($original_translation_start) ; 
                $self->transcript_info->mRNA_start_not_found(1) ;
            }
            $translation->cds_start_not_found(1);  
        }
                 
        if ($exon = $original_end_exon){
            my $new_end = $original_translation_end ;
            if ($translation->end > $exon_length) {    
                $new_end = $exon_length ; 
                $self->transcript_info->mRNA_end_not_found(1) ;
            }
            $translation->end($new_end) ;
            $self->transcript_info->cds_end_not_found(1);
        }    
    }
   
    elsif($exon->strand == -1){
    
        $self->_reset_start_phase($exon, $difference );       
        
        if ($exon == $original_start_exon){
            my $new_start = $original_translation_start - $difference ;
            if ($new_start < 1){
                $new_start = 1 ;
                $self->transcript_info->mRNA_start_not_found(1) ;
            }
            $translation->start($new_start) ;
            $self->transcript_info->cds_start_not_found(1) ;
        }
        
        if ($exon == $original_end_exon){
            my $new_end = $original_translation_end - $difference ; 
            if ($new_end < 1){
                $new_end = 1 ;
                $self->transcript_info->mRNA_end_not_found(1) ;
            }
            $translation->end($new_end);
            $self->transcript_info->cds_end_not_found(1);
        }
    }
    return $difference ;
}


sub _reset_start_phase{
    my ($self , $exon , $difference ) = @_ ;        
    my $new_phase = ($exon->phase + $difference ) % 3 ;    
   
    $exon->phase($new_phase) ;    
}


sub _reset_end_phase {
    my ($self , $exon , $difference) = @_ ;
    my $exon_length = ($exon->end - $exon->start + 1) ;
    my $new_phase = ($exon->phase + $exon_length) %3 ;
    $exon->end_phase($new_phase) ;
}

1;
