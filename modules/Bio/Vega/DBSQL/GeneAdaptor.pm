package Bio::Vega::DBSQL::GeneAdaptor;

use strict;

use Bio::Vega::Gene;
use Bio::Vega::Transcript;
use Bio::EnsEMBL::Utils::Exception qw(throw warning);
use Bio::Vega::Utils::Comparator qw(compare);
use Bio::Vega::AnnotationBroker;
use base 'Bio::EnsEMBL::DBSQL::GeneAdaptor';
use constant CHANGED => 1;
use constant NEW => 2;
use constant  UNCHANGED => 0;
use constant  RESTORED => 3;
use constant  DELETED => 5;

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
  bless $gene, "Bio::Vega::Gene";
  $self->fetch_gene_author($gene);
  my $transcripts=$gene->get_all_Transcripts;
  foreach my $tr (@$transcripts){
	 bless $tr, "Bio::Vega::Transcript";
	 my $ta=$self->db->get_TranscriptAdaptor;
	 $ta->fetch_transcript_author($tr);
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

sub get_deleted_Gene_by_slice{
  my ($self, $gene,$gene_version) = @_;
  unless ($gene || $gene_version){
	 throw("no gene passed on to fetch old gene or no version supplied");
  }
  my $gene_slice=$gene->slice;
  my $gene_stable_id=$gene->stable_id;
  my $db_gene;
  my @out = grep { $_->stable_id eq $gene_stable_id and $_->version eq $gene_version }
    @{$self->SUPER::fetch_all_by_Slice_constraint($gene_slice,'g.is_current = 0 ')};
  if ($#out > 1) {
	 ##test
	 @out = sort {$a->dbID <=> $b->dbID} @out;
	 $db_gene=pop @out;
	 ##test
  }
  else {
	 $db_gene=$out[0];
  }
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

sub fetch_gene_author {
  my ($self,$gene)=@_;
  my $authad = $self->db->get_AuthorAdaptor;
  my $author= $authad->fetch_gene_author($gene->dbID);
  $gene->gene_author($author);
  return $gene;
}

sub get_current_Gene_by_slice{
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

sub update_deleted_gene_status {
  my ($self,$del_gene)=@_;
  ##update deleted genes
  my $tref=$del_gene->get_all_Transcripts();
  my $tran_adaptor=$self->db->get_TranscriptAdaptor;
  my $exon_adaptor=$self->db->get_ExonAdaptor;
  foreach my $del_tran (@$tref) {
	 $del_tran->is_current(0);
	 $tran_adaptor->update($del_tran);
	 foreach my $del_exon (@{$del_tran->get_all_Exons}) {
		$del_exon->is_current(0);
		$exon_adaptor->update($del_exon);
	 }
  }
  $del_gene->is_current(0);
  $self->update($del_gene);
}

=head2 store

 Title   : store
 Usage   : store a gene from the otter_lace client, where genes and its components are attached to a gene_slice or
         : store a gene directly from a script where the gene is attached to the whole chromosome slice.
         : If method_chooser argument is not given then the default is for gene_slice and is for the otter_lace client.
         : Otherwise the argument should be 'chr_whole_slice' for a direct whole chromosome loading.
         : This helps to choose the right method to fetch the database components
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
 Args    : gene to be stored (mandatory)
         : method_chooser (optional), allowed values: 'chr_gene_slice' or 'chr_whole_slice', default value: 'chr_gene_slice'


=cut

sub store{
  
  my ($self,$gene,$method_chooser) = @_;
  my $time=time;
  unless ($gene) {
	 throw("Must enter a Gene object to the store method");
  }
  unless ($gene->isa("Bio::Vega::Gene")) {
	 throw("Object must be a Bio::Vega::Gene object. Currently [$gene]");
  }
  unless ($gene->gene_author) {
	 throw("Bio::Vega::Gene must have a gene_author object set");
  }
  unless ($method_chooser) {
	 $method_chooser='chr_gene_slice';
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
  my $gene_changed=UNCHANGED;

  ##check for a transaction for every gene annotation that is stored
  ##and start a savepoint, for having a checkpoint to rollback to if necessary
  if ($self->db->check_for_transaction != 0){
	 throw "This is non-transactional , cannot proceed storing of gene\n";
  }
  $self->db->savepoint;
  my $db_gene;
  ##create Annotation Broker for comparing
  my $broker=$self->db->get_AnnotationBroker();
  ##deleted gene
  if ($gene->is_current == 0) {
	 $self->update_deleted_gene_status($gene);
	 $gene_changed = DELETED;
  }
  else {
	 ##new gene - assign stable_id
	 my $sida = $self->db->get_StableIdAdaptor();
	 unless ($gene->stable_id){
		$sida->fetch_new_stable_ids_for_Gene($gene);
	 }
	 ##fetch database gene by the right method
	 if ($method_chooser eq 'chr_gene_slice'){
		$db_gene=$self->get_current_Gene_by_slice($gene);
	 }
	 elsif ($method_chooser eq 'chr_whole_slice'){
		$db_gene=$self->fetch_by_stable_id($gene->stable_id);
	 }
	 ##old gene
	 if ( $db_gene && $gene_changed != DELETED) {
		$gene_changed=$broker->check_for_change_in_gene_components($sida,$gene,$method_chooser,$time);
		my $db_version=$db_gene->version;
		if ($gene_changed == UNCHANGED) {
		  $gene_changed=compare($db_gene,$gene);

		}
		$gene->is_current(1);
		$db_gene->is_current(0);
		$self->update($db_gene);
		if ( $gene_changed == CHANGED) {
		  $gene->version($db_version+1);
		  ##add synonym if old gene name is not a current gene synonym
		  $broker->compare_synonyms_add($db_gene,$gene);
		  $gene->created_date($db_gene->created_date);
		  unless ($gene->modified_date){
			 $gene->modified_date($time);
		  }
		}
		else {
		  $gene->version($db_version);
		}

	 }
	 ##if gene is new /restored
	 if ( !$db_gene && $gene_changed != DELETED) {
		my $restored_genes = $self->fetch_all_versions_by_stable_id($gene->stable_id);
		##restored gene
		if (@$restored_genes > 0){
		  my $old_version=1;
		  foreach my $g (@$restored_genes){
			 if ($g->version > $old_version){
				$old_version=$g->version;
			 }
		  }
		  my $old_gene;
		  if ($method_chooser eq 'chr_gene_slice'){
			 $old_gene=$self->get_deleted_Gene_by_slice($gene,$old_version);
		  }
		  elsif ($method_chooser eq 'chr_whole_slice'){
			 $old_gene=$self->fetch_by_stable_id_version($gene->stable_id,$old_version);
		  }
		  $gene->created_date($old_gene->created_date);
		  unless($gene->modified_date){
			 $gene->modified_date($time);
		  }
		  ##check to see change in components
		  $gene->version($old_version);
		  $gene->is_current(1);
		  $gene_changed=$broker->check_for_change_in_gene_components($sida,$gene,$method_chooser);
		  if ($gene_changed == CHANGED)  {
			 $gene->version($old_version+1);
		  }
		  else {
			 ##compare this gene with the highest version of the old genes
			 ##if gene changed
			 $gene_changed=compare($old_gene,$gene);
			 if ($gene_changed == CHANGED){
				$gene->version($old_version+1);
				##add synonym if old gene name is not a current gene synonym
				$broker->compare_synonyms_add($old_gene,$gene);
			 }
			 else {
				$gene_changed=RESTORED;
			 }
		  }
		}
		##new gene
		else {
		  $gene->version(1);
		  $gene->is_current(1);
		  ##check if any of the gene components are old and if so have changed
		  ($gene_changed)=$broker->check_for_change_in_gene_components($sida,$gene,$method_chooser);
		  $gene_changed=NEW;
		  ##storing a new gene and its components
		  #$self->SUPER::store($gene);
		}
	 }
  }

  ##storing gene for the cases of
  ## new gene     :new-2
  ## changed-gene :changed-1
  ## restored gene: restored-with-no-change-3
  ## deleted gene : deleted-5

  if ($gene_changed == NEW || $gene_changed == CHANGED || $gene_changed == RESTORED || $gene_changed == DELETED) {
	 if ($gene_changed == DELETED){
		##As with this current gene object we have already deleted the database gene, and as we want to store the author info
		##for the deleted gene,a new record has to be inserted again with the current copy. dbid, adaptor is made undef, so a new record 
		##can be inserted with the deleted author info
		$gene->dbID(undef);
		$gene->adaptor(undef);
		$gene->modified_date($time);
		my $tref=$gene->get_all_Transcripts();
		foreach my $tran (@$tref) {
		  $tran->dbID(undef);
		  $tran->adaptor(undef);
		  $tran->modified_date($time);
		  if ($tran->translation){
			 $tran->translation->dbID(undef);
			 $tran->translation->adaptor(undef);
			 $tran->translation->modified_date($time);
		  }
		}
	 }
	 if ($gene_changed == NEW){
		unless ($gene->created_date){
		  $gene->created_date($time);
		}
		unless ($gene->modified_date){
		  $gene->modified_date($time);
		}
	 }

	 $self->SUPER::store($gene);
  }

  ##Now that gene and its components have been stored, store the author,and evidence
  if ($gene_changed == CHANGED || $gene_changed == NEW || $gene_changed == RESTORED || $gene_changed == DELETED){
	 ##get author_id and store gene_id-author_id in gene_author table
	 my $aa = $self->db->get_AuthorAdaptor;
	 my $gene_author=$gene->gene_author;
	 $aa->store($gene_author);
	 my $author_id=$gene_author->dbID;
	 $aa->store_gene_author($gene->dbID,$author_id);
	 ##transcript-author, transcript-evidence
	 my $transcripts=$gene->get_all_Transcripts;
	 my $ta = $self->db->get_TranscriptAdaptor;
	 foreach my $tran (@$transcripts){
		##author
		my $tran_author=$tran->transcript_author;
		$aa->store($tran_author);
		my $author_id=$tran_author->dbID;
		$aa->store_transcript_author($tran->dbID,$author_id);
		##evidence
		my $evidence_list=$tran->get_Evidence;
		$ta->store_Evidence($tran->dbID,$evidence_list);
	 }
  }

  ##Also don't forget to delete the deleted transcripts/exons if the status of gene is 'changed-1'
  if ($gene_changed == CHANGED) {
	 ##need not worry for a restored-gene as the old copy is already in a deleted state
	 if ($db_gene){
		my $new_trs=$gene->get_all_Transcripts;
		my $old_trs;
		my $new_tr_count=@$new_trs;
		my $old_tr_count;
		$old_trs=$db_gene->get_all_Transcripts;
		$old_tr_count=@$old_trs;
		if ($old_tr_count > $new_tr_count) {
		  $broker->find_update_deleted_transcripts_status($new_trs,$old_trs);
		}
		my $new_exons=$gene->get_all_Exons;
		my $old_exons;
		my $new_exon_count=@$new_exons;
		my $old_exon_count;
		$old_exons=$db_gene->get_all_Exons;
		$old_exon_count=@$old_exons;
		if ($old_exon_count > $new_exon_count) {
		  $broker->find_update_deleted_exons_status($new_exons,$old_exons);
		}
	 }
	 print STDERR "CHANGED gene:".$gene->stable_id.".".$gene->version."\n-------------------------------------------\n\n";
  }

  ##if after all the comparisons we see that gene and all its components have not changed then just rollback to the checkpoint, 
  ##in case something has been updated during the comparisons.
  if ($gene_changed == UNCHANGED) {
	 $self->db->rollback_to_savepoint;
	 print STDERR "UNCHANGED gene:".$gene->stable_id.".".$gene->version."\n-------------------------------------------\n\n";
  }

  if ($gene_changed == NEW) {
	 print STDERR "NEW gene:".$gene->stable_id.".".$gene->version."\n-------------------------------------------\n\n";
  }
  if ($gene_changed == RESTORED) {
	 print STDERR "RESTORED gene:".$gene->stable_id.".".$gene->version."\n-------------------------------------------\n\n";
  }
  if ($gene_changed == DELETED) {
	 print STDERR "DELETED gene:".$gene->stable_id.".".$gene->version."\n-------------------------------------------\n\n";
  }
  return 1;
}

1;
__END__

=head1 NAME - Bio::Vega::DBSQL::GeneAdaptor

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk
