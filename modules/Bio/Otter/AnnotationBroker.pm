package Bio::Otter::AnnotationBroker;

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::AnnotationBroker::Event;

@ISA = qw(Bio::EnsEMBL::DBSQL::BaseAdaptor);


sub compare_annotations {
    my ($self,$oldgenes,$newgenes) = @_;

    my %oldgenehash;
    my %newgenehash;

    foreach my $g (@$oldgenes) {
	  $oldgenehash{$g->stable_id} = $g;
    }
    foreach my $g (@$newgenes) {
	  $newgenehash{$g->stable_id} = $g;
    }

    # Find deleted genes
    # Change type on deleted genes

    my ($del,$new,$mod) = $self->compare_obj($oldgenes,$newgenes);
    
    my @modgenes = keys %$mod;

    my %modids;

    my @events;

    #print STDERR "GENE : del @$del\n";
    #print STDERR "GENE : new @$new\n";
    #print STDERR "GENE : mod @modgenes\n";

    foreach my $del (@$del) {
       #print $del;
    } 
    foreach my $del (@$new) {
       #print $del;
    } 
    foreach my $del (@modgenes) {
       #print $del;
    } 

    foreach my $geneid (keys %$mod) {
       my $ismodified   = 0;
       my $infomodified = 0;

       my $oldg = $mod->{$geneid}{old};
       my $newg = $mod->{$geneid}{new};

      # Genes which were deleted but have now been restored
      if (defined ($oldg->type) && $oldg->type eq 'obsolete') {
        $modids{$geneid} = 1;
        print STDERR "Found restored gene " . $geneid . "\n";
      }

      # Compare the gene infos to see which have changed
	
	if ($oldg->gene_info->equals($newg->gene_info) == 0) {
	    $infomodified = 1;
            $modids{$geneid} = 1;
	    print STDERR "Found modified gene info " . $geneid . "\n";
	} else {
	    #print STDERR "found same gene info\n";
	}
	
	my @tran1 = @{$oldg->get_all_Transcripts};
	my @tran2 = @{$newg->get_all_Transcripts};

	my ($tdel,$tnew,$tmod) = $self->compare_obj(\@tran1,\@tran2);

        my @modtran = keys %$tmod;

        if (scalar(@$tdel)) {
            print STDERR "Deleted transcripts ";
            foreach my $td (@$tdel) {
               print STDERR $td->stable_id . " ";
            }
            print STDERR "\n";
        }
        if (scalar(@$tnew)) {
            print STDERR "New transcripts ";
            foreach my $td (@$tnew) {
               print STDERR $td->stable_id . " ";
            }
            print STDERR "\n";
        }
        if (scalar(@$tdel) || scalar(@$tnew)) {
          $modids{$geneid} = 1;
        } 

        # Compare the transcripts to see which ones have changed structure
        # and which ones have changed info.
        # Actually - maybe this should be in the store.

        foreach my $tranid (@modtran) {
           
            my $istranmodified = 0;
            my $istraninfomodified = 0;

            my $oldt = $tmod->{$tranid}{old};
            my $newt = $tmod->{$tranid}{new};

            # one could be defined and the other not

            if (defined($oldt->transcript_info) && 
                defined($newt->transcript_info) && 
                $oldt->transcript_info->equals($newt->transcript_info) == 0) {
                $istraninfomodified = 1;
                $infomodified = 1;
                $ismodified = 1;
                #print STDERR "Tran 1\n" . $oldt->transcript_info->toString() . "\n";
                #print STDERR "Tran 2\n" . $newt->transcript_info->toString() . "\n";
                print STDERR "Transcript modified transcript info $tranid \n";
            } else {
                 #print STDERR "Found same transcript info $tranid\n";
            }

            if ($self->compare_transcripts($tmod->{$tranid}{old},
                			   $tmod->{$tranid}{new}) == 0) {

                #print STDERR "Increasing transcript version $tranid\n";

                my $newversion = $tmod->{$tranid}{old}->version()+1;
                 $tmod->{$tranid}{new}->version($newversion);

                if (defined($tmod->{$tranid}{new}->translation)) {
                   my $tnv = $tmod->{$tranid}{new}->translation->version;
                   $tnv++;
                   #print STDERR "Increasing translation version $tnv\n";
                   $tmod->{$tranid}{new}->translation->version($tnv);
                }
                $istranmodified = 1;
                $ismodified = 1;
            } else {
                #print STDERR "Found same transcript $tranid\n";
            }
            
            if ($ismodified == 1) {
                $modids{$geneid} = 1;
            }
        }

	 #print STDERR "TRAN : del @$tdel\n";
	 #print STDERR "TRAN : new @$tnew\n";
	 #print STDERR "TRAN : mod @modtran\n";

	my @newexons = @{$newg->get_all_Exons};
	my @oldexons = @{$oldg->get_all_Exons};

	my ($edel,$enew,$emod) = $self->compare_obj(\@oldexons,\@newexons);
	
	# This is wrong - should we increase the version of modified exons?

	my @modexon = keys %$emod;

	foreach my $ex (@modexon) {
	    if ($self->compare_exons($emod->{$ex}{old},$emod->{$ex}{new}) == 0) {
		# my $ev = $emod->{$ex}{old}->version;
		# $ev++;
		# $emod->{$ex}{new}->version($ev);
          print STDERR "Found modified exon " . $ex ."\n";
         
          #print STDERR " Exon 1 " . $emod->{$ex}{old}->start . " " . $emod->{$ex}{old}->end . " " . $emod->{$ex}{old}->phase . " " . $emod->{$ex}{old}->end_phase . "\n"; 
          #print STDERR " Exon 2 " . $emod->{$ex}{new}->start . " " . $emod->{$ex}{new}->end . " " . $emod->{$ex}{new}->phase . " " . $emod->{$ex}{new}->end_phase . "\n";
          $modids{$geneid} = 1;
	    } else {
		# print "Found same exon\n";
	    }
	}


    } # done comparisons - now need to build arrays

    my $time = time;
    my @tmpids = keys %newgenehash;
    
    push(@tmpids,keys %oldgenehash);
    
    foreach my $geneid (@tmpids) {
	my $gene = $newgenehash{$geneid};
	
	if (!defined($gene)) {
	    $gene = $oldgenehash{$geneid};
	}
	
	if (!defined($gene->created)) {
	    $gene->created($time);
	}
	if (!defined($gene->version)) {
	    $gene->version(1);
	}
	$gene->modified($time);
	
	foreach my $tran (@{$gene->get_all_Transcripts}) {
	    if (!defined($tran->created)) {
		$tran->created($time);
	    }
	    if (!defined($tran->version)) {
		$tran->version(1);
	    }
            if (defined($tran->translation) && !defined($tran->translation->version)) {
            $tran->translation->version(1);
            }
	    $tran->modified($time);
	    
	}
	my $count = 1;
	
	foreach my $exon (@{$gene->get_all_Exons}) {
	    $exon->dbID(undef);
	    
	    if (!defined($exon->created)) {
		$exon->created($time);
	    }
	    if (!defined($exon->version)) {
		$exon->version(1);
	    }
	    $exon->modified($time);
	    
	    
	    $count++;
	}
    }
    
    
    foreach my $g (@$new) {
        print STDERR "Do I have a stableID? : " . $g->stable_id . "\n";

        my $gene_stable_id = $self->db->get_StableIdAdaptor->fetch_new_gene_stable_id;
	my $gene = $newgenehash{$g->stable_id};
        $gene->stable_id($gene_stable_id);
        $gene->version(1);


        foreach my $tran (@{$g->get_all_Transcripts}) {
           my $tid = $self->db->get_StableIdAdaptor->fetch_new_transcript_stable_id;
           $tran->stable_id($tid);
           $tran->version(1);

           if (defined($tran->translation)) {
             my $tid = $self->db->get_StableIdAdaptor->fetch_new_translation_stable_id;
                $tran->translation->stable_id($tid);
                $tran->translation->version(1);
           } 

        }
        foreach my $ex (@{$g->get_all_Exons}) {
            my $eid = $self->db->get_StableIdAdaptor->fetch_new_exon_stable_id;
            $ex->stable_id($eid); 
            $ex->version(1);
        }

	my $event = Bio::Otter::AnnotationBroker::Event->new( -type => 'new',
							      -new => $gene);
	push(@events,$event);
    }
    
    
    # Flag deleted genes
    
    foreach my $g (@$del) {
    
        my $gene = $oldgenehash{$g->stable_id};
        # Already deleted in old set
        if ($gene->type ne 'obsolete') {
            $gene->type('obsolete');
          
            my $gv = $gene->version;
            $gv++;
            $gene->version($gv);
          
            foreach my $tran (@{$gene->get_all_Transcripts}) {
                my $tv = $tran->version;
              
                $tv++;
                $tran->version($tv);
                if (defined($tran->translation)) {
                   my $tnv = $tran->translation->version;
                   $tnv++;
                   $tran->translation->version($tnv);
                }
                foreach my $exon (@{$gene->get_all_Exons}) {
                    my $ev = $exon->version;
                    $ev++;
                    $exon->version($ev);
                }
            }
          
            my $event = Bio::Otter::AnnotationBroker::Event->new( -type => 'deleted',
                                                                  -old  => $gene);
            push(@events,$event);
        }
    }
    
    
    # Modified genes :
    foreach my $id (keys %modids) {
	my $old_gene = $oldgenehash{$id};
        my $new_gene = $newgenehash{$id};
	
        $self->increment_versions($old_gene,$new_gene);

	my $event = Bio::Otter::AnnotationBroker::Event->new( -type => 'modified',
							      -new  => $new_gene,
							      -old  => $old_gene);
	
	push(@events,$event);	    
    }
    

    return @events;
}

sub increment_versions {
  my ($self,$old_gene,$new_gene) = @_;

  my $gv = $old_gene->version;
  $gv++;
  $new_gene->version($gv);
    
  my %oldexonhash;
  foreach my $exon (@{$old_gene->get_all_Exons}) {
    $oldexonhash{$exon->stable_id} = $exon;
  }
  foreach my $exon (@{$new_gene->get_all_Exons}) {
    my $ev;
    if (defined($oldexonhash{$exon->stable_id})) {
      $ev = $oldexonhash{$exon->stable_id}->version;
    } else {
      $ev = $exon->version;
    }
    $ev++;
    print STDERR "Incrementing version to $ev for " . $exon->stable_id . "\n";
    $exon->version($ev);
  }
  my %oldtranshash;
  foreach my $tran (@{$old_gene->get_all_Transcripts}) {
    $oldtranshash{$tran->stable_id} = $tran;
  }
  foreach my $tran (@{$new_gene->get_all_Transcripts}) {
    my $tv;

    if (defined($oldtranshash{$tran->stable_id})) {
      $tv = $oldtranshash{$tran->stable_id}->version;
    } else {
      $tv = $tran->version;
    }

    $tv++;
    $tran->version($tv);

    if (defined($tran->translation)) {
      print STDERR "Increasing translation version " . $tran->stable_id . " " . $tran->translation->stable_id . " "  . $tran->translation . "\n";

      my $tnv = 0;

      if (defined($oldtranshash{$tran->stable_id}) && defined($oldtranshash{$tran->stable_id}->translation)) {
        $tnv = $oldtranshash{$tran->stable_id}->translation->version;
      }

      print STDERR "Existing version " . $tnv . "\n";
      $tnv++;
      $tran->translation->version($tnv);
      print STDERR "New version $tnv\n";
    }
  }
}

sub compare_obj {
    my ($self,$oldobjs,$newobjs) = @_;

    my @del;
    my @new;
    my %mod;

    foreach my $oldobj (@$oldobjs) {
	my $found = 0;

	foreach my $newobj (@$newobjs) {

	    if ($newobj->stable_id eq $oldobj->stable_id) {

		$found = 1;
		$mod{$newobj->stable_id}{old} = $oldobj;
		$mod{$newobj->stable_id}{new} = $newobj;
	    }
	}
	if ($found == 0) {
	    push(@del,$oldobj);
	}
    }

    foreach my $newobj (@$newobjs) {
	if (!defined($mod{$newobj->stable_id})) {
	    push(@new,$newobj);
	}
    }

    return \@del,\@new,\%mod;
}
		

sub compare_transcripts {
    my ($self,$tran1,$tran2) = @_;

    my @exons1 = @{$tran1->get_all_Exons};
    my @exons2 = @{$tran2->get_all_Exons};

    @exons1 = sort {$a->start <=> $b->start} @exons1;
    @exons2 = sort {$a->start <=> $b->start} @exons2;

    if (scalar(@exons1) != scalar(@exons2)) {
	print STDERR "Different numbers of exons (" . scalar(@exons1) . " and " . scalar(@exons2) . "\n";
	return 0;
    }

    while (my $ex1 = shift @exons1) {
	my $ex2 = shift(@exons2);

	if ($self->compare_exons($ex1,$ex2) == 0) {
            print STDERR "Found different exon " . $ex1->stable_id . " " . $ex2->stable_id . "\n";
	    return 0;
	}
    }

    my $tl1 = $tran1->translation;
    my $tl2 = $tran2->translation;

    if (defined($tl1) && defined($tl2)) {
      if ($self->compare_translations($tl1,$tl2) == 0) {
        print STDERR "Translations different\n";
        return 0;
      }
    } elsif (defined($tl1)) {
      print STDERR "No translation in new transcript\n";
      return 0;
    } elsif (defined($tl2)) {
      print STDERR "No translation in old transcript\n";
      return 0;
    }
    return 1;
}

sub compare_exons {
    my ($self,$ex1,$ex2) = @_;

#    print " ---- Comparing 1 " . $ex1->start . "\t" . $ex1->end . "\t" . $ex1->phase . "\t" . $ex1->end_phase . "\n";
#    print " ---- Comparing 2 " . $ex2->start . "\t" . $ex2->end . "\t" . $ex2->phase . "\t" . $ex2->end_phase . "\n";

    if ($ex1->start != $ex2->start) {
        print STDERR "Exon start coords differ " . $ex1->start . " " . $ex2->start . "\n";
        return 0;
    } elsif ($ex1->end  != $ex2->end)  {
        print STDERR "Exon end coords differ " . $ex1->end . " " . $ex2->end . "\n";
        return 0;
    } elsif (defined($ex1->phase) && defined($ex2->phase))  {
        if ($ex1->phase != $ex2->phase) {
          print STDERR "Different phases " . $ex1->phase . " " . $ex2->phase . "\n";
          return 0;
        }
    } elsif (defined($ex1->end_phase) && defined($ex2->end_phase)) {
        if ($ex1->end_phase != $ex2->end_phase) {
          print STDERR "Different end phases " . $ex1->end_phase . " " . $ex2->end_phase . "\n";
          return 0;
        }
    } elsif (defined($ex1->phase) && !defined($ex2->phase)) {
       print STDERR "Phase not defined on exon 2\n";
       return 0;
    } elsif (!defined($ex1->phase) && defined($ex2->phase)) {
       print STDERR "Phase not defined on exon 1\n";
    } elsif (defined($ex1->end_phase) && !defined($ex2->end_phase)) {
       print STDERR "End phase not defined on exon 2\n";
       return 0;
    } elsif (!defined($ex1->end_phase) && defined($ex2->end_phase)) {
       print STDERR "End phase not defined on exon 1\n";
       return 0;
    } 
    return 1;
}

sub compare_translations {
    my ($self,$tl1,$tl2) = @_;

#    print "tl1 start = " . $tl1->start . "\n";
#    print "tl1 end   = " . $tl1->end . "\n";
#    print "tl2 start = " . $tl2->start . "\n";
#    print "tl2 end   = " . $tl2->end . "\n";
    if ($self->compare_exons($tl1->start_Exon,$tl2->start_Exon) == 0) {
        print STDERR "Found different translation start exons " . $tl1->start_Exon->stable_id . " " . $tl2->start_Exon->stable_id . "\n";
        return 0;
    } elsif ($self->compare_exons($tl1->end_Exon,$tl2->end_Exon)  == 0) {
        print STDERR "Found different translation end exons " . $tl1->end_Exon->stable_id . " " . $tl2->end_Exon->stable_id . "\n";
        return 0;
    } elsif ($tl1->start != $tl2->start) {
        print STDERR "Found different translation start coords " . $tl1->start . " " . $tl2->start . "\n";
        return 0;
    } elsif ($tl1->end != $tl2->end) {
        print STDERR "Found different translation end coords " . $tl1->end . " " . $tl2->end . "\n";
        return 0;
    } else {
	return 1;
    }
}
    
1;
