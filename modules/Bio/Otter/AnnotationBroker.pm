package Bio::Otter::AnnotationBroker;

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::AnnotationBroker::Event;

@ISA = qw(Bio::EnsEMBL::DBSQL::BaseAdaptor);


# The name of the author writing changes into the database
sub current_author {
    my( $self, $current_author ) = @_;
    
    if ($current_author) {
        my $class = 'Bio::Otter::Author';
        my $ok = 0;
        eval{ $ok = 1 if $current_author->isa($class) };
        $self->throw("No a $class : '$current_author'") unless $ok;
        $self->{'_current_author'} = $current_author;
    }
    return $self->{'_current_author'};
}

sub compare_feature_sets {
    my( $self, $old_features, $new_features ) = @_;
    
    my %old = map {SimpleFeature_key($_), $_} @$old_features;
    my %new = map {SimpleFeature_key($_), $_} @$new_features;

    # Features that were in the old, but not the new, should be deleted    
    my $delete = [];
    while (my ($key, $old_sf) = each %old) {
        unless ($new{$key}) {
            push(@$delete, $old_sf);
        }
    }

    # Features that are in the new but were not in the old should be saved
    my $save = [];
    while (my ($key, $new_sf) = each %new) {
        unless ($old{$key}) {
            push(@$save, $new_sf);
        }
    }

    return($delete, $save);
}

sub SimpleFeature_key {
    my( $sf ) = @_;
    
    return join('^',
        $sf->analysis->logic_name,
        $sf->start,
        $sf->end,
        $sf->strand,
        # sprintf ensures that 0.5 and 0.5000 become the same string
        sprintf('%g', $sf->score),
        $sf->display_label || '',
        );
}

sub compare_clones {
    my( $self, $old_clones, $new_clones ) = @_;
    
    my $current_author = $self->current_author
        or $self->throw("current_author not set");
    
    my %new = map {$_->embl_id . "." . $_->embl_version, $_} @$new_clones;
    my %old = map {$_->embl_id . "." . $_->embl_version, $_} @$old_clones;
    
    my( @changed );
    foreach my $acc_sv (keys %old) {
        my $old_clone = $old{$acc_sv};
        my $new_clone = $new{$acc_sv}
            or $self->throw(
                "No such clone '$acc_sv' in new annotation:\n"
                . join('', map "$_\n", keys %new));
        unless ($old_clone->clone_info->equals($new_clone->clone_info)) {
            $new_clone->clone_info->author($current_author);
            push(@changed, $new_clone);
        }
    }
    return @changed;
}

sub make_id_version_hash {
    my( $self, $genes ) = @_;
    
    my $stable_version = {};
    foreach my $gene (@$genes) {
        $self->store_stable($stable_version, $gene);
        foreach my $tsct (@{$gene->get_all_Transcripts}) {
            $self->store_stable($stable_version, $tsct);
            if (my $tnsl = $tsct->translation) {
                $self->store_stable($stable_version, $tnsl);
            }
        }
        foreach my $exon (@{$gene->get_all_Exons}) {
            $self->store_stable($stable_version, $exon);
        }
    }
    
    $self->{'_id_version_hash'} = $stable_version;
}

sub increment_obj_version {
    my( $self, $obj ) = @_;
    
    my $stable_version = $self->{'_id_version_hash'};
    
    my $stable = $obj->stable_id
        or $self->throw("No stable_id on object '$obj'");
    my $version = ++$stable_version->{$stable};
    $obj->version($version);

    # Rest is just for the log file:
    my ($type) = ref($obj) =~ /(\w+)$/;
    if ($version > 1) {
        warn "New version '$type' '$stable' = '$version'\n";
    } else {
        warn "New  object '$type' '$stable'\n";
    }
}

sub drop_id_version_hash {
    my( $self ) = @_;
    
    $self->{'_id_version_hash'} = undef;
}

sub store_stable {
    my( $self, $sid_v, $obj ) = @_;
    
    if (my $sid = $obj->stable_id) {
        $sid_v->{$sid} = $obj->version;
    }
}

sub compare_genes {
    my ($self, $old_genes, $new_genes) = @_;
    
    $self->make_id_version_hash($old_genes);

    my $current_author = $self->current_author
        or $self->throw("current_author not set");

    my %oldgenehash;
    my %newgenehash;

    foreach my $g (@$old_genes) {
	$oldgenehash{$g->stable_id} = $g;
    }
    foreach my $g (@$new_genes) {
	$newgenehash{$g->stable_id} = $g;
    }

    # Find deleted genes
    # Change type on deleted genes

    my ($del,$new,$mod) = $self->compare_obj($old_genes, $new_genes);
    
    my %modified_gene_ids;
    my @events;
    foreach my $geneid (keys %$mod) {
        my $gene_modified   = 0;

        my $oldg = $mod->{$geneid}{'old'};
        my $newg = $mod->{$geneid}{'new'};

        # Genes which were deleted but have now been restored
        if (defined ($oldg->type) && $oldg->type eq 'obsolete') {
          $gene_modified = 1;
          print STDERR "Found restored gene '$geneid'\n";
        }

        if (($oldg->description || '') ne ($newg->description || '')) {
            warn "Gene descriptions differ in '$geneid'\n";
            $gene_modified = 1;
        }

        # Compare the gene infos to see which have changed
	if ($oldg->gene_info->equals($newg->gene_info) == 0) {
	    $gene_modified = 1;
	    print STDERR "Found modified gene info '$geneid'\n";
	} else {
	    #print STDERR "found same gene info\n";
	}
	
	my ($tdel,$tnew,$tmod) = $self->compare_obj(
            $oldg->get_all_Transcripts,
            $newg->get_all_Transcripts);

        # Set the author for deleted and new transcripts
        ### No point doing this on deleted transcripts because they are not saved
        #if (scalar(@$tdel)) {
        #    $gene_modified = 1;
        #    print STDERR "Deleted transcripts ";
        #    foreach my $td (@$tdel) {
        #       printf STDERR "  %s\n", $td->stable_id;
        #       $td->transcript_info->author($current_author);
        #    }
        #}
        if (scalar(@$tnew)) {
            $gene_modified = 1;
            print STDERR "New transcripts ";
            foreach my $tn (@$tnew) {
                printf STDERR "  %s\n", $tn->stable_id;
                $tn->transcript_info->author($current_author);
            }
        }

        # Compare the transcripts to see which ones have changed structure
        # and which ones have changed info.
        # Actually - maybe this should be in the store.

        foreach my $tranid (keys %$tmod) {
            my $transcript_modified = 0;
            my $oldt = $tmod->{$tranid}{'old'};
            my $newt = $tmod->{$tranid}{'new'};

            unless ($oldt->transcript_info->equals($newt->transcript_info)) {
                $gene_modified = $transcript_modified = 1;
                #print STDERR "Tran 1\n" . $oldt->transcript_info->toString() . "\n";
                #print STDERR "Tran 2\n" . $newt->transcript_info->toString() . "\n";
                print STDERR "Transcript modified transcript info $tranid \n";
            }

            if ($self->compare_transcripts($oldt, $newt) == 0) {
                $gene_modified = $transcript_modified = 1;
            }
            
            if ($transcript_modified) {
                $newt->transcript_info->author($current_author);
            }
        }

	# We only need to look through all the exons if the gene is modified
        if ($gene_modified == 1) {
            $self->increment_obj_version($newg);
            $newg->gene_info->author($current_author);
            $modified_gene_ids{$geneid} = 1;

            foreach my $tn (@{$newg->get_all_Transcripts}) {
                print STDERR "Transcript: ", $tn->stable_id, "\n";
                $self->increment_obj_version($tn);
                if (my $tp = $tn->translation) {
                    $self->increment_obj_version($tp);
                }
            }

	    # This is wrong - should we increase the version of modified exons?
            ### No - we don't need to store new versions of unchanged exons.
            ### Need to fix.

            foreach my $exon (@{$newg->get_all_Exons}) {
                $self->increment_obj_version($exon);
            }

            #my ($edel, $enew, $emod) = $self->compare_obj(
            #        $newg->get_all_Exons,
            #        $oldg->get_all_Exons,
            #        );
            #my @modexon = keys %$emod;

            #foreach my $ex (@modexon) {
            #    if ($self->compare_exons($emod->{$ex}{old},$emod->{$ex}{new}) == 0) {
            #            print STDERR "Found modified exon " . $ex ."\n";

            #            #print STDERR " Exon 1 " . $emod->{$ex}{old}->start . " " . $emod->{$ex}{old}->end . " " . $emod->{$ex}{old}->phase . " " . $emod->{$ex}{old}->end_phase . "\n"; 
            #            #print STDERR " Exon 2 " . $emod->{$ex}{new}->start . " " . $emod->{$ex}{new}->end . " " . $emod->{$ex}{new}->phase . " " . $emod->{$ex}{new}->end_phase . "\n";
            #            $gene_modified = 1;
            #    } else {
            #    # print STDERR "Found same exon\n";
            #    }
            #}
        }

    } # done comparisons - now need to build arrays
    
    my $time = time;
    
    foreach my $g (@$new) {
        print STDERR "Do I have a stableID? : " . $g->stable_id . "\n";

        my $gene_stable_id = $self->db->get_StableIdAdaptor->fetch_new_gene_stable_id;
	my $gene = $newgenehash{$g->stable_id};
        $self->set_gene_created_version_modified($gene, $time);
        $gene->gene_info->author($current_author);
        $gene->stable_id($gene_stable_id);

        foreach my $tran (@{$g->get_all_Transcripts}) {
           my $tid = $self->db->get_StableIdAdaptor->fetch_new_transcript_stable_id;
           $tran->stable_id($tid);
           $tran->transcript_info->author($current_author);

           if (defined($tran->translation)) {
             my $tid = $self->db->get_StableIdAdaptor->fetch_new_translation_stable_id;
                $tran->translation->stable_id($tid);
           } 

        }
        foreach my $ex (@{$g->get_all_Exons}) {
            my $eid = $self->db->get_StableIdAdaptor->fetch_new_exon_stable_id;
            $ex->stable_id($eid); 
        }

	my $event = Bio::Otter::AnnotationBroker::Event->new( -type => 'new',
							      -new => $gene);
	push(@events,$event);
    }
    
    
    # Flag deleted genes
    
    foreach my $g (@$del) {
        my $gene = $oldgenehash{$g->stable_id};
        $self->set_gene_created_version_modified($gene, $time);

        # Already deleted in old set
        if ($gene->type ne 'obsolete') {
            $gene->type('obsolete');
	    # Think we should all be using increment_obj_version()
            # $gene->version($gene->version + 1);
	    $self->increment_obj_version($gene);
            foreach my $tran (@{$gene->get_all_Transcripts}) {
                # $tran->version($tran->version + 1);
		$self->increment_obj_version($tran);
                if (my $translation = $tran->translation) {
                    # $translation->version($translation->version + 1);
		    $self->increment_obj_version($translation);
                }
                foreach my $exon (@{$gene->get_all_Exons}) {
                    # $exon->version($exon->version + 1);
		    $self->increment_obj_version($exon);
                }
            }
          
            my $event = Bio::Otter::AnnotationBroker::Event->new( -type => 'deleted',
                                                                  -old  => $gene);
            push(@events,$event);
        }
    }
    
    
    # Modified genes :
    foreach my $id (keys %modified_gene_ids) {
	my $old_gene = $oldgenehash{$id};
        my $new_gene = $newgenehash{$id};

	my $event = Bio::Otter::AnnotationBroker::Event->new( -type => 'modified',
							      -new  => $new_gene,
							      -old  => $old_gene);
	
	push(@events,$event);	    
    }
    
    $self->drop_id_version_hash;

    return @events;
}

sub set_gene_created_version_modified {
    my( $self, $gene, $time ) = @_;
    
    # Set created and version on all gene components that don't have them
    # Update the modified time
    $gene->created($time) unless $gene->created;
    $gene->version(1)     unless $gene->version;
    $gene->modified($time);

    foreach my $tran (@{$gene->get_all_Transcripts}) {
        $tran->created($time) unless $tran->created;
        $tran->version(1)     unless $tran->version;
	$tran->modified($time);

        if (my $translation = $tran->translation) {
            $translation->version(1) unless $translation->version;
        }
    }

    foreach my $exon (@{$gene->get_all_Exons}) {
	$exon->dbID(undef);
	$exon->created($time) unless $exon->created;
        $exon->version(1)     unless $exon->version;
	$exon->modified($time);
    }
}

#sub increment_versions {
#    my ($self, $id_version_hash, $new_gene) = @_;
#
#    $self->increment_obj_version($id_version_hash, $new_gene);
#    foreach my $exon (@{$new_gene->get_all_Exons}) {
#        $self->increment_obj_version($id_version_hash, $exon);
#    }
#    foreach my $tsct (@{$new_gene->get_all_Transcripts}) {
#        $self->increment_obj_version($id_version_hash, $tsct);
#        if (my $tnsl = $tsct->translation) {
#            $self->increment_obj_version($id_version_hash, $tnsl);
#        }
#    }
#}

sub compare_obj {
    my ($self, $oldobjs, $newobjs) = @_;

    my( %id_old, @del, @new, %mod );

    # Make a hash of id => old objects (objects already in otter)
    foreach my $oldobj (@$oldobjs) {
	if (my $old_id = $oldobj->stable_id) {
            $id_old{$old_id} = $oldobj;
        } else {
            my $thing = $self->obj_type($oldobj);
            print STDERR "$thing from database missing stable_id\n";
        }
    }

    # Look through all the new objects, and add any without
    # a stable_id, or with a stable id that is not in the list
    # of old objects to the list of potentially modified objects.
    foreach my $newobj (@$newobjs) {
	if (my $new_id = $newobj->stable_id) {
            # Might want to check if two objects in the list
            # of new ones have the same stable_id?
            if (my $oldobj = $id_old{$new_id}) {
                delete($id_old{$new_id});
                $newobj->created($oldobj->created);
                $mod{$new_id}{'old'} = $oldobj;
                $mod{$new_id}{'new'} = $newobj;
                next;
            }
        }
        
        # This is here because the new object may not be new,
        # but could be, for example, an existing transcript
        # that has now been moved into another gene.
        $self->increment_obj_version($newobj);
        
        push(@new, $newobj);
    }

    # We deleted any old objects we found from %id_old, so any left
    # are not in the new set, and have therefore been deleted.
    while (my ($id, $obj) = each %id_old) {
        my $thing = $self->obj_type($obj);
        print STDERR "$thing '$id' was not found\n";
        push(@del, $obj);
    }

    return(\@del, \@new, \%mod);
}

sub obj_type {
    my( $self, $obj ) = @_;
    
    my ($type) = ref($obj) =~ /([^:]+)$/;
    return $type;
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

    my $tl_old = $tran1->translation;
    my $tl_new = $tran2->translation;

    if ($tl_old and $tl_new) {
      if ($self->compare_translations($tl_old,$tl_new) == 0) {
        print STDERR "Translations different\n";
        return 0;
      }
    } elsif ($tl_old) {
      print STDERR "No translation in new transcript\n";
      return 0;
    } elsif ($tl_new) {
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
