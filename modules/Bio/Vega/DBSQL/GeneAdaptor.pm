package Bio::Vega::DBSQL::GeneAdaptor;

use strict;

use Bio::Vega::Gene;
use Bio::Vega::Transcript;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Vega::Utils::Comparator qw(compare);
use Bio::Vega::AnnotationBroker;
use base 'Bio::EnsEMBL::DBSQL::GeneAdaptor';

use constant UNCHANGED => 0;
use constant CHANGED   => 1;
use constant NEW       => 2;
use constant RESTORED  => 3;
use constant DELETED   => 5;

sub fetch_by_stable_id  {
  my ($self, $stable_id) = @_;
  my ($gene) = $self->SUPER::fetch_by_stable_id($stable_id);
  if ($gene){
	 $self->reincarnate_gene($gene);
  }
  return $gene;
}

sub fetch_by_name {
  my ($self,$genename)=@_;
  unless ($genename) {
	 throw("Must enter a gene name to fetch a Gene");
  }
  my $genes=$self->fetch_by_attribute_code_value('name',$genename);
  my $gene;
  my $dbid;
  if ($genes){
	 my $stable_id;
	 foreach my $g (@$genes){
		if ($stable_id && $stable_id ne $g->stable_id){
		  die "more than one gene has the same name\n";
		}
		$stable_id=$g->stable_id;
		if ($dbid ){
		  if ($g->dbID > $dbid){
			 $dbid=$g->dbID;
		  }
		}
		else {
		  $dbid=$g->dbID;
		}
	 }
  }
  if ($dbid){
	 print STDOUT "gene found\n";
	 $gene=$self->fetch_by_dbID($dbid);
	 $self->reincarnate_gene($gene);
  }

  return $gene;
}

sub fetch_by_attribute_code_value {
  my ($self,$attrib_code,$attrib_value)=@_;
  my $sth=$self->prepare("SELECT ga.gene_id ".
								 "FROM attrib_type a , gene_attrib ga ".
                         "WHERE ga.attrib_type_id = a.attrib_type_id and ".
								 "a.code=? and ga.value =?");
  $sth->execute($attrib_code,$attrib_value);
  my @array = @{$sth->fetchall_arrayref()};
  $sth->finish();
  my @geneids = map {$_->[0]} @array;
  
  if ($#geneids > 0){
	return $self->fetch_all_by_dbID_list(\@geneids);
  }
  else {
	 return 0;
  }

}

sub fetch_stable_id_by_name {

  # can search either genename or transname by name or synonym,
  # support CASE INSENSITIVE search
  # returns a reference to a list of gene stable ids if successful
  # $mode is either 'gene' or 'transcript' which corresponds to genename or transname
  # search uses LIKE command

  my ($self, $name, $mode) = @_;

  unless ($name) {
	 throw("Must enter a gene name to fetch a Gene");
  }

  my $mode_attrib;
  ($mode eq 'gene') ? ($mode_attrib = 'gene_attrib') : ($mode_attrib = 'transcript_attrib');

  my ($attrib_code,$attrib_value, $gsids, $join);

  foreach ( qw(name synonym) ){
	$attrib_code = $_;
	$attrib_value = $name;

	if ( $mode eq 'gene' ){
	  $attrib_value =~ s/-\d+$//;
	  $join = "m.gene_id = ma.gene_id";
	}
	else {
	  $attrib_value =~ /(.*)-\d+.*/;   # eg, ABO-001
	  $attrib_value =~ /(.*\.\d+).*/;  # want sth. like RP11-195F19.20, trim away eg, -001, -002-2-2
	  $attrib_value = $1;
 	  $join = "m.transcript_id = ma.transcript_id";
	}

	$attrib_value = lc($attrib_value); # for case-insensitive comparison later

	my $sth=$self->prepare(qq{
							  SELECT distinct gsi.stable_id, ma.value
							  FROM gene_stable_id gsi, $mode m, attrib_type a , $mode_attrib ma
							  WHERE gsi.gene_id=m.gene_id
							  AND $join
							  AND ma.attrib_type_id = a.attrib_type_id
							  AND a.code=?
							  AND ma.value LIKE ?
							 }
						  );

	$sth->execute($attrib_code, qq{$attrib_value%});

	while ( my ($gsid, $value) = $sth->fetchrow ){
	  # exclude eg, SET7 SETX where search is 'SET%' (ie, allow SET-2)
	  if ( lc($value) eq $attrib_value or lc($value) =~ /$attrib_value-\d+/ ){
		push(@$gsids, $gsid);
	  }
	}
	$sth->finish();
  }

  return $gsids;
}

sub reincarnate_gene {
  my ($self,$gene)=@_;

  bless $gene, 'Bio::Vega::Gene';

  my $author = $self->db->get_AuthorAdaptor->fetch_gene_author($gene->dbID);
  $gene->gene_author($author);

  my $ta=$self->db->get_TranscriptAdaptor;
  foreach my $transcript (@{ $gene->get_all_Transcripts }) {
	 bless $transcript, 'Bio::Vega::Transcript';
	 $ta->fetch_transcript_author($transcript);
  }

  return $gene;
}

sub fetch_all_by_Slice  {
  my ($self,$slice,$logic_name,$load_transcripts)  = @_;
  my $latest_genes = [];
  my ($genes) = $self->SUPER::fetch_all_by_Slice($slice,$logic_name,$load_transcripts);
  if ($genes){
	 foreach my $gene(@$genes){
		$self->reincarnate_gene($gene);
		my $tsct_list = $gene->get_all_Transcripts;
		for (my $i = 0; $i < @$tsct_list;) {
		  my $transcript = $tsct_list->[$i];
		  my( $t_name );
		  eval{
			 my $t_name_att = $transcript->get_all_Attributes('name') ;
			 if ($t_name_att->[0]){
				$t_name=$t_name_att->[0]->value;
			 }
		  };
		  if ($@) {
			 die sprintf("Error getting name of %s %s (%d):\n$@", 
							 ref($transcript), $transcript->stable_id, $transcript->dbID);
		  }
		  my $exons_truncated = $transcript->truncate_to_Slice($slice);
		  my $ex_list = $transcript->get_all_Exons;
		  my $message;
		  my $truncated=0;
		  if (@$ex_list) {
			 $i++;
			 if ($exons_truncated) {
				$message ="Transcript '$t_name' has $exons_truncated exon";
				if ($exons_truncated > 1) {
				  $message .= 's that are not in this slice';
				} else {
				  $message .= ' that is not in this slice';
				}
				$truncated=1;
				
			 }
		  }
		  else {
			 # This will fail if get_all_Transcripts() ceases to return a ref
			 # to the actual list of Transcripts inside the Gene object
			 splice(@$tsct_list, $i, 1);
			 $message="Transcript '$t_name' has no exons within the slice";
			 $truncated=1;
		  }
		  if ($truncated == 1) {
			 my $remark_att = Bio::EnsEMBL::Attribute->new(-CODE => 'remark',-NAME => 'Remark',-DESCRIPTION => 'Annotation Remark',-VALUE => $message);
			 my $gene_att=$gene->get_all_Attributes;
			 push @$gene_att, $remark_att ;
			 $gene->truncated_flag(1);
			 print STDERR "Found a truncated gene";
		  }
		}
		# Remove any genes that don't have transcripts left.
		if (@$tsct_list) {
		  push(@$latest_genes, $gene);
		}
	 }
  }
  return $latest_genes;
}

sub get_deleted_Gene_by_slice {
  my ($self, $gene, $gene_version) = @_;
  unless ($gene || $gene_version) {
	 throw("no gene passed on to fetch old gene or no version supplied");
  }
  my $gene_stable_id=$gene->stable_id;
  my @out =
    sort {$b->dbID <=> $a->dbID }
    grep { $_->stable_id eq $gene_stable_id and $_->version eq $gene_version }
    @{$self->SUPER::fetch_all_by_Slice_constraint($gene->slice,'g.is_current = 0 ')};

  my $db_gene=$out[0];
  if ($db_gene){
	 $self->reincarnate_gene($db_gene);
  }
  return $db_gene;
}

sub fetch_by_stable_id_version  {
  my ($self, $stable_id,$version) = @_;
  unless ($stable_id || $version) {
	 throw("Must enter a gene stable id:$stable_id and version:$version to fetch a Gene");
  }
  my $constraint = "gsi.stable_id = '$stable_id' AND gsi.version = '$version'";
  my ($gene) = @{ $self->generic_fetch($constraint) };
  $self->reincarnate_gene($gene);
  return $gene;
}

sub fetch_by_transcript_stable_id_constraint {

  # Ensembl has fetch_by_transcript_stable_id
  # but this is restricted to is_current == 1

  # here, is_current is not restricted to 1
  # use for tracking gene history
  # returns a reference to a list of vega gene objects

    my ($self, $trans_stable_id) = @_;

    my $sth = $self->prepare(qq(
        SELECT  tr.gene_id
		FROM	transcript tr, transcript_stable_id tsi
        WHERE   tsi.stable_id = ?
        AND     tr.transcript_id = tsi.transcript_id
    ));

    $sth->execute($trans_stable_id);

	my ($genes, $seen_genes);

	# a transcript may be pointed to > 1 gene stable_ids
	while ( my $geneid = $sth->fetchrow ){
	  throw("No gene id found: invalid gene stable id") unless $geneid;
	  my $gene = $self->fetch_by_dbID($geneid);
	  my $gsid = $gene->stable_id;
	  $seen_genes->{$gsid}++;
	  push(@$genes, $self->reincarnate_gene($gene)) if $seen_genes->{$gsid} == 1;
	}
	
    return $genes;
}

sub get_current_Gene_by_slice {
  my ($self, $gene) = @_;
  unless ($gene){
	 throw("no gene passed on to fetch old gene");
  }
  my $gene_slice=$gene->slice;
  my $gene_stable_id=$gene->stable_id;
  my @out = grep { $_->stable_id eq $gene_stable_id }
    @{ $self->fetch_all_by_Slice_constraint($gene_slice,'g.is_current = 1 ')};
  if ($#out > 1) {
	 die "there are more than one gene retrived\n";
  }
  my $db_gene=$out[0];
  if ($db_gene){
	 $self->reincarnate_gene($db_gene);
  }
  return $db_gene;
}

sub find_and_update_deleted_components { # either transcripts or exons
    my ($self, $component_adaptor, $old_components, $new_components) = @_;

    my %newhash = map { $_->stable_id => $_} @$new_components;
    my %oldhash = map { $_->stable_id => $_} @$old_components;

    while (my ($stable_id, $old_component) = each %oldhash) {
        unless ($newhash{$stable_id}) {
            $old_component->is_current(0);
            $component_adaptor->update($old_component);
        }
    }
}

    # iterate through last_db_versions of gene components and update the ones marked non-current:
sub update_changed_components {
    my ($self, $gene) = @_;

    my $db_gene = $gene->last_db_version();
    if($db_gene && !$db_gene->is_current()) {
        $self->db->get_GeneAdaptor->update($db_gene);
    }

    my $ta = $self->db->get_TranscriptAdaptor;
    for my $transcript (@{$gene->get_all_Transcripts()}) {
        my $db_transcript=$transcript->last_db_version();
        if($db_transcript && !$db_transcript->is_current()) {
            $ta->update($db_transcript);
        }
    }

    my $ea = $self->db->get_ExonAdaptor;
    for my $exon (@{$gene->get_all_Exons()}) {
        my $db_exon=$exon->last_db_version();
        if($db_exon && !$db_exon->is_current()) {
            $ea->update($db_exon);
        }
    }
}

    #
    # Fetch and reincarnate the last version of the gene with the same stable_id (whether current or not).
    # If $on_whole_chromosome is true, do not use any mapping, just fetch directly on the chromosome.
    #
sub fetch_last_version {
    my ($self, $gene, $on_whole_chromosome) = @_;

    my $gene_stable_id=$gene->stable_id;

    my @candidates = $on_whole_chromosome
        ? @{ $self->generic_fetch( "gsi.stable_id = '$gene_stable_id'" ) }
        : (grep { $_->stable_id eq $gene_stable_id }
               @{ $self->fetch_all_by_Slice($gene->slice()) });

    unless(scalar @candidates) {
        return;
    }

    my $last = shift @candidates;
    foreach my $candidate (@candidates) {
        if($candidate->version > $last->version) {
            $last = $candidate;
        }
    }

    return $self->reincarnate_gene($last);
}

=head2 store

 Title   : store
 Usage   : store a gene from the otter_lace client, where genes and its components are attached to a gene_slice or
         : store a gene directly from a script where the gene is attached to the whole chromosome slice.
         :
 Function: Every gene is compared with the database gene on itself and all its components and versions allocated accordingly.
         : Version is incremented only if there is a change otherwise not. Re-using of exons between version of gene and between
         : transcripts of the same gene.
         : stores a deleted gene
         : stores a changed gene
         : stores a restored gene
         : stores a new gene
         : does not store if gene is unchanged.
 Example :
 Returns : 1 if succeeded
 Args    :
         : $gene to be stored (mandatory)
         :
         : $on_whole_chromosome (optional, default==false)
         : is a binary flag that controls whether the object to be stored is attached to slice
         : (and in this case all the fetching of components for comparison also happens from that slice)
         : or, if the slice is not known, everything is stored on whole chromosomes (as when we convert old otter
         : databases into new lutra ones).
         :
         : $time_now is the time to be considered the current time. Also useful when converting otter->lutra.

=cut

sub store {
    my ($self, $gene, $on_whole_chromosome, $time_now) = @_;

    $time_now       ||= time;

    unless ($gene) {
     throw("Must enter a Gene object to the store method");
    }
    unless ($gene->isa("Bio::Vega::Gene")) {
     throw("Object must be a Bio::Vega::Gene object. Currently [$gene]");
    }
    unless ($gene->gene_author) {
     throw("Bio::Vega::Gene must have a gene_author object set");
    }

    my $slice = $gene->slice;
    unless ($slice) {
     throw "gene does not have a slice attached to it, cannot store gene\n";
    }
    unless ($slice->coord_system) {
     throw("Coord System not set in gene slice \n");
    }
    unless ($gene->slice->adaptor){
     my $sa = $self->db->get_SliceAdaptor();
     $gene->slice->adaptor($sa);
    }

    my $broker=$self->db->get_AnnotationBroker();

        ## assign stable_ids for all new components at once:
    $broker->fetch_new_stable_ids_or_prefetch_latest_db_components($gene, $on_whole_chromosome);

    my $gene_state;

        # first step: compare the subcomponents to their previous versions PLUS some side-effects
        # (set timestamps and versions, but do not update anything in the database)
    my $gene_changed = $broker->transcripts_diff($gene, $time_now);

    if(my $db_gene=$gene->last_db_version() ) { # the gene is not NEW,
                   # so we either CHANGE, RESTORE(possibly changed), DELETE(possibly changed) or leave UNCHANGED

            # second step: since there was a previous version, it may have changed:
        $gene_changed ||= compare($db_gene,$gene);

        $gene_state = $gene->is_current()
            ? $db_gene->is_current()
                ? $gene_changed
                    ? CHANGED
                    : UNCHANGED
                : RESTORED
            : DELETED;

        if($gene_state==UNCHANGED) { # just leave as soon as possible
            print STDERR "UNCHANGED gene:".$db_gene->stable_id.".".$db_gene->version."\n-------------------------------------------\n\n";
            return 0;
        }
                    
        ##add synonym if old gene name is not a current gene synonym
        $broker->compare_synonyms_add($db_gene,$gene);

            # If there was either a structural or mere author change,
            # but the gene is still associated with the last fetchable version,
            # it has to be dissociated from the DB to get a new set of dbIDs:
        if($gene->dbID() && ($gene->dbID() == $db_gene->dbID())) {
            $gene->dbID(undef);
            $gene->adaptor(undef);
            foreach my $tran (@{ $gene->get_all_Transcripts() }) {
                $tran->dbID(undef);
                $tran->adaptor(undef);
                    # NB: exons do not need to be duplicated
                if ($tran->translation){
                    $tran->translation->dbID(undef);
                    $tran->translation->adaptor(undef);
                }
            }
        }

        $gene->version($db_gene->version()+1);          # CHANGED||RESTORED||DELETED will affect the author, so get a new version
        $gene->created_date($db_gene->created_date());
		$db_gene->is_current(0);

            # If a gene is marked is non-current, we assume it was intended for deletion.
            # We also assume unsetting is_current() is the only thing needed to declare such intention.
            # So let's mark all of its' components for deletion as well:
        if($gene_state == DELETED) {
            foreach my $del_tran (@{ $gene->get_all_Transcripts() }) {
                $del_tran->is_current(0);
                foreach my $del_exon (@{$del_tran->get_all_Exons}) {
                    $del_exon->is_current(0);
                }
            }
        } else { # but still changed! - mark the deleted/changed components non-current and update them

                # transcripts and exons under $db_gene that are not under $gene anymore:
            $self->find_and_update_deleted_components(
                $self->db->get_TranscriptAdaptor, $db_gene->get_all_Transcripts, $gene->get_all_Transcripts);
            $self->find_and_update_deleted_components(
                $self->db->get_ExonAdaptor, $db_gene->get_all_Exons, $gene->get_all_Exons);

                # anything under $gene that has is_current()==0 must be updated as well
            $self->update_changed_components($gene);
        }

    } else { # NEW gene, but may have old components (as a result of a split)

        $gene_state=NEW;

        $gene->version(1);
        $gene->created_date($time_now);
        $gene->is_current(1);
    }
    $gene->modified_date($time_now);

        # NB: this is here only to cover the cases where setting timestamps failed in the components
        #
#    foreach my $tran (@{ $gene->get_all_Transcripts() }) {
#        $tran->created_date($time_now)  unless $tran->created_date();
#        $tran->modified_date($time_now) unless $tran->modified_date();
#        foreach my $exon (@{ $tran->get_all_Exons() }) {
#            $exon->created_date($time_now)  unless $exon->created_date();
#            $exon->modified_date($time_now) unless $exon->modified_date();
#        }
#        if(my $trl = $tran->translation) {
#            $trl->created_date($time_now)  unless $trl->created_date();
#            $trl->modified_date($time_now) unless $trl->modified_date();
#        }
#    }

        # Here we assume that the parent method will update all is_current() fields,
        # trusting the values that we have just set.
    $self->SUPER::store($gene);

        ## Now store the author and evidence:
    my $aa = $self->db->get_AuthorAdaptor;

        ##get author_id and store gene_id-author_id in gene_author table
    my $gene_author=$gene->gene_author;
    $aa->store($gene_author);
    my $author_id=$gene_author->dbID;
    $aa->store_gene_author($gene->dbID,$author_id);

        ##transcript-author, transcript-evidence
    my $ta = $self->db->get_TranscriptAdaptor;
    foreach my $tran (@{ $gene->get_all_Transcripts }) {
        my $tran_author=$tran->transcript_author;
        $aa->store($tran_author);
        my $author_id=$tran_author->dbID;
        $aa->store_transcript_author($tran->dbID,$author_id);

        my $evidence_list=$tran->get_Evidence;
        $ta->store_Evidence($tran->dbID,$evidence_list);
    }

    if($gene_state == CHANGED) {
        print STDERR "CHANGED gene:".$gene->stable_id.".".$gene->version."\n-------------------------------------------\n\n";
    } elsif ($gene_state == NEW) {
        print STDERR "NEW gene:".$gene->stable_id.".".$gene->version."\n-------------------------------------------\n\n";
    } elsif ($gene_state == RESTORED) {
        print STDERR "RESTORED gene:".$gene->stable_id.".".$gene->version."\n-------------------------------------------\n\n";
    } elsif ($gene_state == DELETED) {
        print STDERR "DELETED gene:".$gene->stable_id.".".$gene->version."\n-------------------------------------------\n\n";
    }

    return 1;
}

1;
__END__

=head1 NAME - Bio::Vega::DBSQL::GeneAdaptor

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk
