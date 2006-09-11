package Bio::Vega::ContigLockBroker;

use strict;
use Bio::EnsEMBL::Utils::Exception qw ( throw warning );
use Bio::Vega::ContigLock;


sub client_hostname {
    my( $self, $client_hostname ) = @_;
    if ($client_hostname) {
        $self->{'_client_hostname'} = $client_hostname;
    }
    return $self->{'_client_hostname'};
}


### CloneLockBroker should have an Author and a CloneLockAdaptor attached
### so it doesn't need to inherit from BaseAdaptor


##ported/tested
sub check_locks_exist_by_slice {
  my ($slice,$author,$db) = @_;
  if (!defined($slice)) {
	 throw("Can't check contig locks on a slice if no slice");
  }
  if (!defined($author)) {
	 throw("Can't check contig locks on a slice with no author");
  }
  if (!$slice->isa("Bio::EnsEMBL::Slice")) {
	 throw("[$slice] is not a Bio::EnsEMBL::Slice");
  }
  if (!$author->isa("Bio::Vega::Author")) {
	 throw("[$author] is not a Bio::Vega::Author");
  }
  my $contig_list = Contig_listref_from_Slice($slice);
  my $aptr = $db->get_ContigLockAdaptor;
  my $sa=$db->get_SliceAdaptor();
  my( @locks );
  foreach my $contig (@$contig_list) {
	 my $ctg_seq_region_id=$sa->get_seq_region_id($contig);
	 my $lock = $aptr->fetch_by_contig_id($ctg_seq_region_id)
		or throw(sprintf "Contig [%s] not locked by [%s]\n", $ctg_seq_region_id,$author->name);
	 unless ($lock->author->name eq $author->name) {
		throw("Author [" . $author->name . "] doesn't own lock for $contig");
	 }
	 push(@locks, $lock);
  }
  return @locks;
}

##ported
sub check_no_locks_exist_by_slice {
  my ($self,$slice,$author) = @_;
  if (!defined($slice)) {
	 throw("Can't check clone locks on a slice if no slice");
  }
  if (!defined($author)) {
	 throw("Can't check clone locks on a slice with no author");
  }
  if (!$slice->isa("Bio::EnsEMBL::Slice")) {
	 throw("[$slice] is not a Bio::EnsEMBL::Slice");
  }
  if (!$author->isa("Bio::Vega::Author")) {
	 throw("[$author] is not a Bio::Vega::Author");
  }
  my $contig_list = Contig_listref_from_Slice($slice);
  my $aptr       = $self->get_ContigLockAdaptor;
  my $sa=$db->get_SliceAdaptor();
  foreach my $contig (@$contig_list) {
	 my $ctg_seq_region_id=$sa->get_seq_region_id($contig);
	 throw("Contig '". $contig->seq_region_name ."' is locked\n")
		if $aptr->fetch_by_contig_id($ctg_seq_region_id);
  }
  return 1;
}

##ported
sub lock_clones_by_slice {
  my ($self,$slice,$author) = @_;
  if (!defined($slice)) {
	 throw("Can't lock clones on a slice if no slice");
  }
  if (!defined($author)) {
	 throw("Can't lock clones on a slice with no author");
  }
  if (!$slice->isa("Bio::EnsEMBL::Slice")) {
	 throw("[$slice] is not a Bio::EnsEMBL::Slice");
  }
  if (!$author->isa("Bio::Otter::Author")) {
	 throw("[$author] is not a Bio::Otter::Author");
  }
  my $contig_list = Contig_listref_from_Slice($slice);
  my $aptr       = $self->get_ContigLockAdaptor;
  my $sa=$db->get_SliceAdaptor;
  my( @new,               # locks we manange to create
		@existing,          # locks that already existed
		%existing_contig,    # contigs that had locks existing (for nice error message)
	 );
  foreach my $contig (@$contig_list) {
	 my $ctg_seq_region_id = $sa->get_seq_region_id($contig)
		or throw('Contig does not have dbID set');
	 my $lock = Bio::Vega::CloneLock->new(
													  -author     => $author,
													  -contig_id   => $ctg_seq_region_id,
													  -hostname   => $self->client_hostname,
													 );
	 eval {
		$self->get_ContigLockAdaptor->store($lock);
	 };
	 if ($@) {
		my $exlock = $self->get_ContigLockAdaptor->fetch_by_contig_id($ctg_seq_region_id);
		push(@existing, $exlock);
		$existing_contig{$contig_id} = $contig;
	 } else {
		push(@new, $lock);
	 }
  }
  if (@existing) {
	 # Unlock any that we just locked (could do this with rollback?)
	 foreach my $lock (@new) {
		$aptr->remove($lock);
	 }
	 # Give a nicely formatted error message about what is already locked
	 my $lock_error_str = "Can't lock contigs because some are already locked:\n";
	 foreach my $lock (@existing) {
		my $contig = $existing_contig{$lock->contig_id};
		my $ctg_seq_region_id = $sa->get_seq_region_id($contig)
		  $lock_error_str .= sprintf "  '%s' has been locked by '%s' since %s\n",
			 $ctg_seq_region_id, $lock->author->name, scalar localtime($lock->timestamp);
	 }
	 throw($lock_error_str);
  }
}

##ported
sub remove_by_slice {
  my ($self,$slice,$author) = @_;
  my $contig_list = Contig_listref_from_Slice($slice);
  my $aptr       = $self->get_CloneLockAdaptor;
  my $sa=$db->get_SliceAdaptor;
  foreach my $contig (@$contig_list) {
	 my $ctg_seq_region_id=$sa->get_seq_region_id($contig);
	 if (my $lock = $self->get_CloneLockAdaptor->fetch_by_contig_id($ctg_seq_region_id)) {
		unless ($lock->author->name eq $author->name) {
		  throw("Author [" . $author->name . "] doesn't own lock for $clone");
		}
		$aptr->remove($lock);
	 } else {
		$self->warn("Can't unlock contig [$clone]. Lock doesn't exist");
	 }
  }
}

##ported/tested
sub Contig_listref_from_Slice {
    my( $slice ) = @_;
    my $contig_list = [];
	 my $slice_projection = $slice->project('contig');
	 foreach my $seg (@$slice_projection) {
		my $contig_slice = $seg->to_Slice();
		push(@$contig_list, $contig_slice);
	 }
    return $contig_list;
}




1;
