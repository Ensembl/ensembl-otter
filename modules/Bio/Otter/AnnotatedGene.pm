package Bio::Otter::AnnotatedGene;

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::Gene;

@ISA = qw(Bio::EnsEMBL::Gene);

sub new {
  my($class,@args) = @_;

  my $self = $class->SUPER::new(@args);
  
  my ($gene_info)  = $self->_rearrange([qw(
					   INFO
					   )],@args);
  
  $self->gene_info($gene_info);

  return $self;
}

=head2 gene_info

 Title   : gene_info
 Usage   : $obj->gene_info($newval)
 Function: 
 Example : 
 Returns : value of gene_info
 Args    : newvalue (optional)


=cut

sub gene_info {
   my ($obj,$value) = @_;

   if( defined $value) {

       if ($value->isa("Bio::Otter::GeneInfo")) {
	   $obj->{'gene_info'} = $value;
       } else {
	   $obj->throw("Argument to gene_info must be a Bio::Otter::GeneInfo object.  Currently is [$value]");
       }
    }
    return $obj->{'gene_info'};

}

=head2 toXMLString

 Title   : toXMLString
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub toXMLString{
    my ($self) = shift;


# determine if gene is on a slice
    my $exons = $self->get_all_Exons;
    my $offset = 0;

    if (scalar(@$exons)) {
      my $contig = $exons->[0]->contig;
      if (defined($contig) && $contig->isa("Bio::EnsEMBL::Slice")) {
        $offset = $contig->chr_start-1;
      }
    }



    my $str = "<locus>\n";
    my $stableid = "";

    if (defined($self->stable_id)) { $stableid = $self->stable_id;}
   
    $str .= " <locus_type>" . $self->type . "</locus_type>\n";
    $str .= " <stable_id>" . $stableid . "</stable_id>\n";

    my $info = $self->gene_info;

    if (defined($info)) {
        my $name = "";
        if (my $n = $info->name) {
            $name = $n->name;
        }
	$str .= " <name>"      . $name      . "</name>\n";

        $str .= '<known>' . $gene_info->is_known . '</known>';

	my @syn = $info->synonym;

	@syn = sort {$a->name cmp $b->name} @syn;

	foreach my $syn (@syn) {
	    $str .= " <synonym>" . $syn->name . "<\/synonym>\n";
	}

        my @rem = $info->remark;
        @rem = sort {$a->remark cmp $b->remark} @rem;

	foreach my $rem (@rem) {
            my $remstr = $rem->remark;
            $remstr =~ s/\n/ /g;
	    $str .= " <remark>" . $remstr . "</remark>\n";
	}
        my $name;
        my $email;

        if (my $author = $info->author) {
            $str .= $author->toXMLString;
        }
    }

    my @tran = @{$self->get_all_Transcripts};

    @tran = sort by_stable_id_or_name @tran;

    foreach my $tran (@tran) {
        my $tranid = "";
        if (defined($tran->stable_id)) {
           $tranid = $tran->stable_id;
        }
	$str .= " <transcript>\n";
	$str .= "  <stable_id>$tranid</stable_id>\n";
	
	my $tinfo = $tran->transcript_info;

	if (defined($tinfo)) {

            if (my $author = $info->author) {
                $str .= $author->toXMLString;
            }

	    foreach my $remstr (sort map $_->remark, $tinfo->remark) {
                $remstr =~ s/\n/ /g;
		$str .= "  <remark>$remstr</remark>\n";
	    }
	   
            my $classname = "";
	    my $tname    = "";

            if (defined($tinfo->class)) {
               if (defined($tinfo->class->name)) {
                  $classname = $tinfo->class->name;
               }
            }
 
	    if (defined($tinfo->name)) {
		$tname = $tinfo->name;
	    }

            foreach my $method (qw{
                cds_start_not_found
                cds_end_not_found
                mRNA_start_not_found
                mRNA_end_not_found
                })
            {
                $str .= "  <$method>" . ($tinfo->$method() || 0) . "</$method>\n";
            }
	    
	    $str .= "  <transcript_class>$classname</transcript_class>\n";
	    $str .= "  <name>$tname</name>\n";
	    
            $str .= "  <evidence_set>\n";

            my @evidence = $tinfo->evidence;
            @evidence = sort {$a->name cmp $b->name} @evidence;

            foreach my $ev (@evidence) {
              $str .= "    <evidence>\n";
              $str .= "      <name>" . $ev->name . "</name>\n";
              $str .= "      <type>" . $ev->type . "</type>\n";
              $str .= "    </evidence>\n";
            }
            $str .= "  </evidence_set>\n";
	}


        my $tran_low  = undef;
        my $tran_high = undef;
        if (my $tl = $tran->translation) {
          my $strand = $tl->start_Exon->strand;
          $tran_low  = $tran->coding_region_start;
          $tran_high = $tran->coding_region_end;
          $str .= "  <translation_start>" . (($strand == 1) ? ($tran_low  + $offset) : ($tran_high + $offset)) . "</translation_start>\n";
          $str .= "  <translation_end>"   . (($strand == 1) ? ($tran_high + $offset) : ($tran_low  + $offset)) . "</translation_end>\n";
            if (my $tl_id = $tl->stable_id) {
                $str .= "  <translation_stable_id>$tl_id</translation_stable_id>\n";
            }
        }

	$str .= "  <exon_set>\n";

        my @exon = @{$tran->get_all_Exons;};

        @exon = sort {$a->start <=> $b->start} @exon;

        my $cds_snf = "";
        if (defined($tinfo->cds_start_not_found)) {
          $cds_snf = $tinfo->cds_start_not_found;
        }
	foreach my $ex (@exon) {
            my $stable_id = "";
            if (defined($ex->stable_id)) {
               $stable_id = $ex->stable_id;
            }
	    $str .= "   <exon>\n";
	    $str .= "    <stable_id>" . $stable_id . "</stable_id>\n";
	    $str .= "    <start>"     . ($ex->start+$offset)     . "</start>\n";
	    $str .= "    <end>"       . ($ex->end+$offset)       . "</end>\n";
	    $str .= "    <strand>"    . $ex->strand    . "</strand>\n";
            # Only coding exons have frame set
            if (defined($tran_low) && defined($tran_high) && 
                $ex->end >= $tran_low && $ex->start <= $tran_high) {
              my $frame;
              # Frame for first coding exon is set to 0 
              if ($ex == $tran->translation->start_Exon) {
	        $frame = 0;
              } else {
	        $frame = ((3-$ex->phase)%3);
              }
	      $str .= "    <frame>" . $frame . "</frame>\n";
            }
	    $str .= "   </exon>\n";
	}
	$str .= "  </exon_set>\n";

	$str .= " </transcript>\n";
    }
    $str .= "</locus>\n";
    
    return $str;
}

sub by_stable_id_or_name {

  my $astableid = "";
  my $bstableid = "";

  if (defined($a->stable_id)) {$astableid = $a->stable_id;}
  if (defined($b->stable_id)) {$bstableid = $b->stable_id;}
  
  my $cmpVal = ($astableid cmp $bstableid);

  if (!$cmpVal) {
    if (!defined($b->transcript_info->name) && !defined($a->transcript_info->name)) {
      $cmpVal = 0;
    } elsif (!defined($a->transcript_info->name)) {
      $cmpVal = 1;
    } elsif (!defined($b->transcript_info->name)) {
      $cmpVal = -1;
    } else {
      $cmpVal = ($a->transcript_info->name cmp $b->transcript_info->name);
    }
  }
  return $cmpVal;
}

sub stable_id {
  my ($self,$arg) = @_;

  if (defined($arg)) {
    $self->SUPER::stable_id($arg);
    $self->gene_info->gene_stable_id($arg);
  }

  return $self->SUPER::stable_id($arg);
}



sub equals {
    my ($self,$obj) = @_;

    if (!defined($obj)) {
	$self->throw("Need an object to compare with");
    }
    if (!$obj->isa("Bio::Otter::AnnotatedGene")) {
	$self->throw("[$obj] not a Bio::Otter::AnnotatedGene");
    }
    
    if ($self->gene_info->equals($obj->gene_info) == 0 ) {
	print "Gene info different\n";
    } else {
	print " - Equal gene info\n";
    }
}
    
1;
