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

sub compare_assembly_tag_sets {
  my( $self, $old_tag_set, $new_tag_set ) = @_;

  my %old = map {AssemblyTag_key($_), $_} @$old_tag_set;
  my %new = map {AssemblyTag_key($_), $_} @$new_tag_set;

  # Features that were in the old, but not the new, should be deleted
  my $delete = [];
  while (my ($key, $old_at) = each %old) {
    unless ($new{$key}) {
      push(@$delete, $old_at);
    }
  }

  # Features that are in the new but were not in the old should be saved
  my $save = [];
  while (my ($key, $new_at) = each %new) {
    unless ($old{$key}) {
      push(@$save, $new_at);
    }
  }

  return($delete, $save);
}

sub AssemblyTag_key {
    my( $at ) = @_;

    return join('^',
        $at->tag_type,
        $at->start,
        $at->end,
	$at->tag_info,	
	$at->strand	
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
        $self->store_stable($stable_version, $gene, 'gene');
        foreach my $tsct (@{$gene->get_all_Transcripts}) {
            $self->store_stable($stable_version, $tsct, 'transcript');
            if (my $tnsl = $tsct->translation) {
                $self->store_stable($stable_version, $tnsl, 'translation');
            }
        }
        foreach my $exon (@{$gene->get_all_Exons}) {
            $self->store_stable($stable_version, $exon, 'exon');
        }
    }

    $self->{'_id_version_hash'} = $stable_version;
}

sub store_stable {
    my( $self, $sid_v, $obj, $type ) = @_;

    if (my $sid = $obj->stable_id) {
        my $get_max = $self->db->prepare(qq{
            SELECT MAX(version)
            FROM ${type}_stable_id
            WHERE stable_id = ?
            });
        $get_max->execute($sid);
        my ($max) = $get_max->fetchrow;
        $max ||= 0;
        
        my $this_version = $obj->version;
        $this_version = $max if $max > $this_version;
        if (my $version = $sid_v->{$sid}) {
            $sid_v->{$sid} = $this_version if $this_version > $version;
        } else {
            $sid_v->{$sid} = $this_version;
        }
    }
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

sub compare_genes {
    my ($self, $old_genes, $new_genes) = @_;

    $self->make_id_version_hash($old_genes);

    my $current_author = $self->current_author
      or $self->throw("current_author not set");

    my %oldgenehash;
    my %newgenehash;

    foreach my $g (@$old_genes) {
        $oldgenehash{ $g->stable_id } = $g;
    }
    foreach my $g (@$new_genes) {
        $newgenehash{ $g->stable_id } = $g;
    }

    # Find deleted genes
    # Change type on deleted genes

    my ($del, $new, $mod) = $self->compare_obj($old_genes, $new_genes);

    my %modified_gene_ids;
    my @events;
    foreach my $geneid (keys %$mod) {
        my $gene_modified = 0;

        my $oldg = $mod->{$geneid}{'old'};
        my $newg = $mod->{$geneid}{'new'};

        # Genes which were deleted but have now been restored
        if (defined($oldg->type) && $oldg->type eq 'obsolete') {
            print STDERR "Found restored gene '$geneid'\n";
            $gene_modified = 1;
        }
        elsif ($oldg->type ne $newg->type) {
            print STDERR "Gene '$geneid' changed type\n";
            $gene_modified = 1;
        }

        if (($oldg->description || '') ne ($newg->description || '')) {
            warn "Gene descriptions differ in '$geneid'\n";
            $gene_modified = 1;
        }

        # Compare the gene infos to see which have changed
        if ($oldg->gene_info->equals($newg->gene_info) == 0) {
            $gene_modified = 1;
            print STDERR "Found modified gene info '$geneid'\n";

            # See if gene name has changed, and if it has add
            # old as alias unless it is already an alias

            if ($oldg->gene_info->name->name ne $newg->gene_info->name->name) {

                my $exist = 0;

                if ($oldg->gene_info->synonym) {
                    foreach my $sym ($oldg->gene_info->synonym) {
                        $exist++ if $sym->name eq $oldg->gene_info->name->name;
                    }
                }

                if ($exist == 0) {
                    my $gsynonym = new Bio::Otter::GeneSynonym;
                    $gsynonym->gene_info_id($newg->gene_info->dbID);
                    $gsynonym->name($oldg->gene_info->name->name);
                    $newg->gene_info->synonym($gsynonym);
                }
                else {
                    print STDERR "Synonym "
                      . $oldg->gene_info->name->name
                      . " already exists - no action\n";
                }
            }
        }
        else {

            #print STDERR "found same gene info\n";
        }

        my ($tdel, $tnew, $tmod) =
          $self->compare_obj($oldg->get_all_Transcripts,
            $newg->get_all_Transcripts);

        # Set the author for deleted and new transcripts
        if (scalar(@$tdel)) {
            $gene_modified = 1;
            ### No point doing this on deleted transcripts because they are not saved
            #foreach my $td (@$tdel) {
            #   printf STDERR "  %s\n", $td->stable_id;
            #   $td->transcript_info->author($current_author);
            #}
        }
        if (scalar(@$tnew)) {
            $gene_modified = 1;
            print STDERR "New transcripts\n";
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
            my $oldt                = $tmod->{$tranid}{'old'};
            my $newt                = $tmod->{$tranid}{'new'};

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
            $newg->gene_info->author($current_author);
            $modified_gene_ids{$geneid} = 1;
        }

    }    # done comparisons - now need to build arrays

    my $time = time;

    foreach my $g (@$new) {
        print STDERR "Do I have a stableID? : " . $g->stable_id . "\n";
        
        ### Why get this from the newgenehash?
        my $gene = $newgenehash{ $g->stable_id }
            or die "No gene with stable_id '", $g->stable_id, "'";

        $self->set_gene_created_version_modified($gene, $time);
        $gene->gene_info->author($current_author);

        foreach my $tran (@{ $g->get_all_Transcripts }) {
            $tran->transcript_info->author($current_author);
        }

        $self->increment_versions_in_gene($gene);
        my $event = Bio::Otter::AnnotationBroker::Event->new(
            -type => 'new',
            -new  => $gene
        );
        push(@events, $event);
    }

    # Flag deleted genes

    foreach my $g (@$del) {
        my $gene = $oldgenehash{ $g->stable_id };
        $self->set_gene_created_version_modified($gene, $time);

        # Already deleted in old set
        if ($gene->type ne 'obsolete') {
            $gene->type('obsolete');

            $self->increment_versions_in_gene($gene);
            my $event = Bio::Otter::AnnotationBroker::Event->new(
                -type => 'deleted',
                -old  => $gene
            );
            push(@events, $event);
        }
    }

    # Modified genes :
    foreach my $id (keys %modified_gene_ids) {
        my $old_gene = $oldgenehash{$id};
        my $new_gene = $newgenehash{$id};

        $self->increment_versions_in_gene($new_gene);
        my $event = Bio::Otter::AnnotationBroker::Event->new(
            -type => 'modified',
            -new  => $new_gene,
            -old  => $old_gene
        );

        push(@events, $event);
    }

    $self->drop_id_version_hash;

    return @events;
}

sub increment_versions_in_gene {
    my( $self, $gene ) = @_;

    $self->increment_obj_version($gene);

    foreach my $tn (@{$gene->get_all_Transcripts}) {
        $self->increment_obj_version($tn);
        if (my $tp = $tn->translation) {
            $self->increment_obj_version($tp);
        }
    }

    # This is wrong - should we increase the version of modified exons?
    ### No - we don't need to store new versions of unchanged exons.
    ### Need to fix.

    foreach my $exon (@{$gene->get_all_Exons}) {
        $self->increment_obj_version($exon);
    }
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

sub compare_obj {
    my ($self, $oldobjs, $newobjs) = @_;

    my( %id_old, @del, @new, %mod );

    # Make a hash of id => old objects (objects already in otter)
    foreach my $oldobj (@$oldobjs) {
	if (my $old_id = $oldobj->stable_id) {
            $id_old{$old_id} = $oldobj;
        } else {
            my $thing = $self->obj_type($oldobj);
            die "$thing from database missing stable_id\n";
        }
    }

    # Look through all the new objects, and add any with a stable
    # id that is not in the list of old objects to the list of
    # potentially modified objects.
    foreach my $newobj (@$newobjs) {
	my $new_id = $newobj->stable_id
            or die "Object '$newobj' in data being saved is missing its stable_id";
        # Might want to check if two objects in the list
        # of new ones have the same stable_id?
        if (my $oldobj = $id_old{$new_id}) {
            delete($id_old{$new_id});
            $newobj->created($oldobj->created);
            $mod{$new_id}{'old'} = $oldobj;
            $mod{$new_id}{'new'} = $newobj;
            next;
        }

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

    if ($ex1->start != $ex2->start) {
        print STDERR "Exon start coords differ " . $ex1->start . " " . $ex2->start . "\n";
        return 0;
    }
    elsif ($ex1->end != $ex2->end)  {
        print STDERR "Exon end coords differ " . $ex1->end . " " . $ex2->end . "\n";
        return 0;
    }
    elsif ($ex1->strand != $ex2->strand) {
        print STDERR "Exon strands differ " . $ex1->strand . " " . $ex2->strand . "\n";
        return 0;
    }
    else {
        my $phase1 = $ex1->phase || 'undef';
        my $phase2 = $ex2->phase || 'undef';
        if ($phase1 ne $phase2) {
            print STDERR "Different phases $phase1 $phase2\n";
            return 0;
        }
        else {
            my $end_phase1 = $ex1->end_phase || 'undef';
            my $end_phase2 = $ex2->end_phase || 'undef';
            if ($end_phase1 ne $end_phase2) {
                print STDERR "Different end phases $end_phase1 $end_phase2\n";
                return 0;
            }
        }
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
