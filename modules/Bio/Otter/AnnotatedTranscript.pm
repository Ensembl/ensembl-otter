package Bio::Otter::AnnotatedTranscript;

use strict;
use warnings;
use Carp;

use Bio::Vega::Utils::XmlEscape qw{ xml_escape xml_unescape };

use base qw( Bio::EnsEMBL::Transcript );

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

=head2 flush_Translation

 Title   : flush_Translation
 Usage   : $obj->flush_Translation()
 Function:
 Example :
 Returns :
 Args    :


=cut

sub flush_Translation {
  my $self = shift;

  $self->{'translation'}     = undef;
  $self->{'_translation_id'} = undef;

  return;
}

sub patch_Translation {
    my ($self) = @_;
    
    return unless my $tsl = $self->translation;
    my $patched = 0;
    if ($tsl->start > $tsl->start_Exon->length) {
        $tsl->start($tsl->start_Exon->length);
        $patched++;
    }
    if ($tsl->end > $tsl->end_Exon->length) {
        $tsl->end($tsl->end_Exon->length);
        $patched++;
    }
    return $patched;
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

    my $exons_truncated = 0;
    my $in_translation_zone = 0;
    my $slice_length = $slice->length;
    my $ex_list = $self->get_all_Exons;
    for (my $i = 0; $i < @$ex_list;) {
        my $exon = $ex_list->[$i];
        my $exon_start = $exon->start;
        my $exon_end   = $exon->end;
        if(($exon->contig != $slice) or ($exon_end < 1) or ($exon_start > $slice_length)
           or ($exon->{_previously_truncated})) {
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
                $exon->{_previously_truncated} = 1;
                $trunc_flag = 1;
                $exon->start(1);
            }
            if ($exon->end > $slice_length) {
                #warn "truncating exon that overlaps end of slice";
                $exon->{_previously_truncated} = 1;
                $trunc_flag = 1;
                $exon->end($slice_length);
            }
            $exons_truncated++ if $trunc_flag;
        }
    }

    ### Hack until we fiddle with translation stuff
    if ($exons_truncated) {
        $self->{'translation'}     = undef
        $self->{'_translation_id'} = undef;
    }

    return $exons_truncated;
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

    return;
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

    return;
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

    return;
}


sub _reset_end_phase {
    my ($self , $exon , $difference) = @_ ;
    my $exon_length = ($exon->end - $exon->start + 1) ;
    my $new_phase = ($exon->phase + $exon_length) %3 ;
    $exon->end_phase($new_phase) ;
    return;
}

sub toXMLString {
    my ($self, $offset) = @_;
    
    confess("No offset given") unless defined $offset;

    my $str = "";

    my $tranid = "";
    if (defined($self->stable_id)) {
        $tranid = $self->stable_id;
    }
    $str .= "  <transcript>\n";
    $str .= "    <stable_id>$tranid</stable_id>\n";

    my $tinfo = $self->transcript_info;

    if (defined($tinfo)) {

        if (my $author = $tinfo->author) {
            $str .= $author->toXMLString;
        }

        foreach my $remstr (sort map { $_->remark } $tinfo->remark) {
            $remstr =~ s/\n/ /g;
            $str .= "    <remark>" . xml_escape($remstr) . "</remark>\n";
        }

        foreach my $method (
            qw{
            cds_start_not_found
            cds_end_not_found
            mRNA_start_not_found
            mRNA_end_not_found
            }
          )
        {
            $str .=
              "  <$method>" . ($tinfo->$method() || 0) . "</$method>\n";
        }

        my $classname = $tinfo->class->name || "";
        my $tname     = $tinfo->name        || "";

        $str .= "    <transcript_class>$classname</transcript_class>\n";
        $str .= "    <name>$tname</name>\n";

        $str .= "    <evidence_set>\n";

        my $evidence = $tinfo->get_all_Evidence;
        @$evidence = sort { $a->name cmp $b->name } @$evidence;

        foreach my $ev (@$evidence) {
            $str .= "      <evidence>\n";
            $str .= "        <name>" . $ev->name . "</name>\n";
            $str .= "        <type>" . $ev->type . "</type>\n";
            $str .= "      </evidence>\n";
        }
        $str .= "    </evidence_set>\n";
    }

    my $tran_low  = undef;
    my $tran_high = undef;
    if (my $tl = $self->translation) {
        my $strand = $tl->start_Exon->strand;
        $tran_low  = $self->coding_region_start;
        $tran_high = $self->coding_region_end;
        $str .= sprintf "    <translation_start>%d</translation_start>\n",
            $offset + ($strand == 1 ? $tran_low : $tran_high);
        $str .= sprintf "    <translation_end>%d</translation_end>\n",
            $offset + ($strand == 1 ? $tran_high : $tran_low);
        if (my $tl_id = $tl->stable_id) {
            $str .=
              "    <translation_stable_id>$tl_id</translation_stable_id>\n";
        }
    }

    $str .= "    <exon_set>\n";

    my @exon = @{ $self->get_all_Exons; };

    @exon = sort { $a->start <=> $b->start } @exon;

    my $cds_snf = "";
    if (defined($tinfo->cds_start_not_found)) {
        $cds_snf = $tinfo->cds_start_not_found;
    }
    foreach my $ex (@exon) {
        my $stable_id = "";
        if (defined($ex->stable_id)) {
            $stable_id = $ex->stable_id;
        }
        $str .= "      <exon>\n";
        $str .= "        <stable_id>" . $stable_id . "</stable_id>\n";
        $str .= "        <start>" . ($ex->start + $offset) . "</start>\n";
        $str .= "        <end>" . ($ex->end + $offset) . "</end>\n";
        $str .= "        <strand>" . $ex->strand . "</strand>\n";

        # Only coding exons have frame set
        ### Do we need to test for translation region - why not
        ### just rely on phase of exon, which will be -1 if non-coding?
        if (   defined($tran_low)
            && defined($tran_high)
            && $ex->end >= $tran_low
            && $ex->start <= $tran_high)
        {
            my $phase = $ex->phase;
            my $frame = $phase == -1 ? 0 : (3 - $phase) % 3;
            $str .= "        <frame>" . $frame . "</frame>\n";
        }
        $str .= "      </exon>\n";
    }
    $str .= "    </exon_set>\n";

    $str .= "  </transcript>\n";
    
    return $str;
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

