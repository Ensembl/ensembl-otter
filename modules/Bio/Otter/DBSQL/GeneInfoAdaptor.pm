package Bio::Otter::DBSQL::GeneInfoAdaptor;

use strict;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::GeneInfo;

use vars qw(@ISA);

@ISA = qw ( Bio::EnsEMBL::DBSQL::BaseAdaptor);

# new is inherieted

=head2 _generic_sql_fetch

 Title   : _generic_sql_fetch
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub _generic_sql_fetch {
	my( $self, $where_clause ) = @_;

	my $sql = q{
		SELECT gene_info_id,
		       gene_stable_id,
                       author_id,
                       timestamp
		FROM gene_info }
	. $where_clause;

	my $sth = $self->prepare($sql);
	$sth->execute;

	if (my $ref = $sth->fetchrow_hashref) {
		my $info_id   = $ref->{gene_info_id};
		my $stable_id  = $ref->{gene_stable_id};
		my $author_id = $ref->{author_id};
		my $timestamp = $ref->{timestamp};

		#  Should probably do this all in the sql           
		my $aad = $self->db->get_AuthorAdaptor();
		my $author = $aad->fetch_by_dbID($author_id);

		my $geneinfo = new Bio::Otter::GeneInfo(-dbId            => $info_id,
                                                        -gene_stable_id  => $stable_id,
                                                        -author          => $author,
                                                        -timestamp       => $timestamp);
	
                # Now get the remarks using the GeneRemarkAdaptor	

		my @remark = $self->db->get_GeneRemarkAdaptor->list_by_gene_info_id($info_id);
		
		$geneinfo->remark(@remark);
		
		# And the synonyms

		my @syn   = $self->db->get_GeneSynonymAdaptor->list_by_gene_info_id($info_id);

		$geneinfo->synonym(@syn);

		# And the gene name

		my $name  = $self->db->get_GeneNameAdaptor->fetch_by_gene_info_id($info_id);
		
		$geneinfo->name($name);

		return $geneinfo;	 	

	} else {
		return;
	}
}

=head2 fetch_by_dbID

 Title   : fetch_by_dbID
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_dbID {
	my ($self,$id) = @_;

	if (!defined($id)) {
		$self->throw("Id must be entered to fetch a GeneInfo object");
	}

	my $info = $self->_generic_sql_fetch("where gene_info_id = $id");

	return $info;
}

=head2 fetch_by_stable_id

 Title   : fetch_by_stable_id
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_stable_id{
   my ($self,$id) = @_;

   if (!defined($id)) {
       $self->throw("Id must be entered to fetch a GeneInfo object");
   }

   my $info = $self->_generic_sql_fetch("where gene_stable_id = \'$id\'");

   return $info;

}


=head2 store

 Title   : store
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut


sub store {
  my ($self,$geneinfo) = @_;

  if (!defined($geneinfo)) {
      $self->throw("Must provide a geneinfo object to the store method");
  } elsif (! $geneinfo->isa("Bio::Otter::GeneInfo")) {
      $self->throw("Argument must be a GeneInfo object to the store method.  Currently is [$geneinfo]");
  }

  $self->db->get_AuthorAdaptor->store($geneinfo->author);
  
  my $sql = "insert into gene_info(gene_stable_id,author_id,timestamp) values (\'" . 
      $geneinfo->gene_stable_id . "\'," . 
      $geneinfo->author->dbID . ",now())";
  
  my $sth = $self->prepare($sql);
  my $rv  = $sth->execute();
  
  $self->throw("Failed to insert geneinfo for gene " . $geneinfo->gene_stable_id) unless $rv;
  
  my $sth2 = $self->prepare("select last_insert_id()");
  my $res = $sth2->execute;
  my $row = $sth2->fetchrow_hashref;

  $sth2->finish;
  
  $geneinfo->dbID($row->{'last_insert_id()'});

  # First the name
  my $name = $geneinfo->name;
  $name->gene_info_id($geneinfo->dbID);

  $self->db->get_GeneNameAdaptor->store($name);

  # Now the synonyms
  foreach my $syn ($geneinfo->synonym) {
      $syn->gene_info_id($geneinfo->dbID);
      $self->db->get_GeneSynonymAdaptor->store($syn);
  }
  # And finally the remarks

  foreach my $rem ($geneinfo->remark) {
      $rem->gene_info_id($geneinfo->dbID);
      $self->db->get_GeneRemarkAdaptor->store($rem);
  }  

  return 1;
}

1;
