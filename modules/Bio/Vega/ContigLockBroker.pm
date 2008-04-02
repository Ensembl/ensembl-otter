package Bio::Vega::ContigLockBroker;

use strict;
use Bio::EnsEMBL::Utils::Exception qw ( throw warning );
use Bio::Vega::ContigLock;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );

sub new {
  my($class,@args) = @_;
  my $self = bless {}, $class;
  my ($hostname)  =
        rearrange([qw(HOSTNAME)],@args);
  $self->client_hostname($hostname);
  return $self;
}

sub client_hostname {
    my( $self,$hostname ) = @_;
    if ($hostname) {
        $self->{'hostname'} = $hostname;
    }
    return $self->{'hostname'};
}


### CloneLockBroker should have an Author and a CloneLockAdaptor attached
### so it doesn't need to inherit from BaseAdaptor


##ported/tested
sub check_locks_exist_by_slice {
  my ($self,$slice,$author,$db) = @_;
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

  my $contig_list = $self->Contig_listref_from_Slice($slice);
  my $aptr = $db->get_ContigLockAdaptor;
  my $sa=$db->get_SliceAdaptor();
  my( @locks );
  foreach my $contig (@$contig_list) {
	 my $ctg_seq_region_id=$sa->get_seq_region_id($contig);
	 my $lock = $aptr->fetch_by_contig_id($ctg_seq_region_id)
		or throw(sprintf "Contig [%s] not locked\n", $ctg_seq_region_id);
	 unless ($lock->author->name eq $author->name) {
		throw("Author [" . $author->name . "] doesn't own lock for $contig");
	 }
	 push(@locks, $lock);
  }
  return @locks;
}

##ported
sub check_no_locks_exist_by_slice {
  my ($self,$slice,$author,$db) = @_;
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
  my $contig_list = $self->Contig_listref_from_Slice($slice);
  my $aptr       = $self->get_ContigLockAdaptor;
  my $sa=$db->get_SliceAdaptor();
  foreach my $contig (@$contig_list) {
	 my $ctg_seq_region_id=$sa->get_seq_region_id($contig);
	 throw("Contig '". $contig->seq_region_name ."' is locked\n")
		if $aptr->fetch_by_contig_id($ctg_seq_region_id);
  }
  return 1;
}

sub lock_by_object {
    my ($self, $obj, $author) = @_;
    
    return $self->lock_clones_by_slice($obj->feature_Slice, $author, $obj->adaptor->db);
}

##ported && tested
sub lock_clones_by_slice {
  my ($self,$slice,$author,$db) = @_;
  if (!defined($slice)) {
	 throw("Can't lock clones on a slice if no slice");
  }
  if (!defined($author)) {
	 throw("Can't lock clones on a slice with no author");
  }
  if (!$slice->isa("Bio::EnsEMBL::Slice")) {
	 throw("[$slice] is not a Bio::EnsEMBL::Slice");
  }
  if (!$author->isa("Bio::Vega::Author")) {
	 throw("[$author] is not a Bio::Vega::Author");
  }
  my $contig_list = $self->Contig_listref_from_Slice($slice);
  my $aptr       = $db->get_ContigLockAdaptor;
  my $sa=$db->get_SliceAdaptor;

    my(
        @successful_locks,  # Locks we manange to create
        $lock_error_str,    # Any locking problems
    );
    foreach my $contig (@$contig_list) {

        my( $lock, $ctg_seq_region_id );
	    eval {
	        $ctg_seq_region_id = $sa->get_seq_region_id($contig)
		        or die sprintf "Failed to fetch seq_region_id for '%s'", $contig->seq_region_name;
	        $lock = Bio::Vega::ContigLock->new(
                 -author       => $author,
                 -contig_id    => $ctg_seq_region_id,
                 -hostname     => $self->client_hostname,
            );
		    $db->get_ContigLockAdaptor->store($lock);
	    };

	    if ($@) {
            $lock_error_str .= sprintf "Failed to lock contig '%s'", $contig->seq_region_name;
            if (my $exlock = $db->get_ContigLockAdaptor->fetch_by_contig_id($ctg_seq_region_id)) {
                $lock_error_str .= sprintf " already locked by '%s' on '%s' since %s\n",
                    $exlock->author->name,
                    $exlock->hostname,
                    scalar localtime($exlock->timestamp);
            } else {
                # Locking failed for another reason.
                $lock_error_str .= ": $@\n";
                last;   # No point trying to lock other contigs
            }
	    } else {
		    push(@successful_locks, $lock);
	    }
    }
  
    if ($lock_error_str) {
        # Unlock any that we just locked (could do this with rollback?)
        foreach my $lock (@successful_locks) {
            $aptr->remove($lock);
        }
        throw($lock_error_str);
    }
}

sub remove_by_object {
    my ($self, $obj, $author) = @_;
    
    return $self->remove_by_slice($obj->feature_Slice, $author, $obj->adaptor->db);
}

##ported
sub remove_by_slice {
  my ($self,$slice,$author,$db) = @_;
  my $contig_list = $self->Contig_listref_from_Slice($slice);
  my $aptr       = $db->get_ContigLockAdaptor;
  my $sa=$db->get_SliceAdaptor;
  foreach my $contig (@$contig_list) {
	 my $ctg_seq_region_id=$sa->get_seq_region_id($contig);
	 if (my $lock = $db->get_ContigLockAdaptor->fetch_by_contig_id($ctg_seq_region_id)) {
		unless ($lock->author->name eq $author->name) {
		  throw("Author [" . $author->name . "] doesn't own lock for $contig");
		}
		$aptr->remove($lock);
	 } else {
		warning("Can't unlock contig [$contig]. Lock doesn't exist");
	 }
  }
}

##ported/tested
sub Contig_listref_from_Slice {
  my ($self,$slice)  = @_;

  my $contig_list = [];
  my $slice_projection = $slice->project('contig');
  foreach my $contig_seg (@$slice_projection) {
	 my $contig_slice = $contig_seg->to_Slice();
	# my $assembly_offset = $contig_slice->start()-1;
	# $contig_slice->start($contig_seg->from_start+ $assembly_offset);
	# $contig_slice->end($contig_seg->from_end   + $assembly_offset);
	 push(@$contig_list, $contig_slice);
  }

  return $contig_list;
}

1;
