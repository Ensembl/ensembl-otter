package Bio::Otter::CloneLockBroker;

use vars qw(@ISA);
use strict;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::CloneLock;

# Shouldn't have this
@ISA = qw(Bio::EnsEMBL::DBSQL::BaseAdaptor);


sub check_locks_exist_by_slice {
    my ($self,$slice,$author) = @_;

    if (!defined($slice)) {
	$self->throw("Can't check clone locks on a slice if no slice");
    } 
    if (!defined($author)) {
	$self->throw("Can't check clone locks on a slice with no author");
    }

    if (!$slice->isa("Bio::EnsEMBL::Slice")) {
	$self->throw("[$slice] is not a Bio::EnsEMBL::Slice");
    }
    if (!$author->isa("Bio::Otter::Author")) {
	$self->throw("[$author] is not a Bio::Otter::Author");
    }

    my @locks;
    my %clones = $self->get_clones_versions($slice);

    foreach my $clone (keys %clones) {
	
	my $lock = $self->get_CloneLockAdaptor->fetch_by_clone_id_version($clone,$clones{$clone});
	
	if (defined($lock)) {
	    if ($lock->author->name ne $author->name ||
		$lock->author->email ne $author->email) {
		$self->throw("Author [" . $author->name . "] doesn't own lock for $clone");
	    } else {
		push(@locks,$lock);
	    }
	} else {
	    $self->throw("Clone [$clone] not locked\n");
	}
    }
    return @locks;
}

sub check_no_locks_exist_by_slice {
    my ($self,$slice,$author) = @_;

    if (!defined($slice)) {
	$self->throw("Can't check clone locks on a slice if no slice");
    } 
    if (!defined($author)) {
	$self->throw("Can't check clone locks on a slice with no author");
    }

    if (!$slice->isa("Bio::EnsEMBL::Slice")) {
	$self->throw("[$slice] is not a Bio::EnsEMBL::Slice");
    }
    if (!$author->isa("Bio::Otter::Author")) {
	$self->throw("[$author] is not a Bio::Otter::Author");
    }

    my @locks;

    my %clones = $self->get_clones_versions($slice);
    
    foreach my $clone (keys %clones) {

	my $lock = $self->get_CloneLockAdaptor->fetch_by_clone_id_version($clone,$clones{$clone});
	
	if (defined($lock)) {
	    $self->throw("Clone lock already exists for clone $clone");
	}
    }

    return @locks;
}


sub lock_clones_by_slice {
    my ($self,$slice,$author) = @_;

    if (!defined($slice)) {
	$self->throw("Can't lock clones on a slice if no slice");
    } 
    if (!defined($author)) {
	$self->throw("Can't lock clones on a slice with no author");
    }

    if (!$slice->isa("Bio::EnsEMBL::Slice")) {
	$self->throw("[$slice] is not a Bio::EnsEMBL::Slice");
    }
    if (!$author->isa("Bio::Otter::Author")) {
	$self->throw("[$author] is not a Bio::Otter::Author");
    }

    my %clones = $self->get_clones_versions($slice);

    my %locks;
    my %newlocks;

    foreach my $clone (keys %clones) {
	my $lock = new Bio::Otter::CloneLock(-author => $author, 
					     -id     => $clone, 
					     -version => $clones{$clone});
	eval {
	    $self->get_CloneLockAdaptor->store($lock); 
	};  
	if ($@) {
	    my $exlock = $self->get_CloneLockAdaptor->fetch_by_clone_id_version($clone,$clones{$clone});
	    $locks{$clone} = $exlock;   
            #last;
	} else {
	    $newlocks{$clone} = $lock;  
	}   
    }

    my @lock = keys %locks;

    if (scalar(@lock)) {
        my $lock_error_str = "Can't lock clones because some are already locked\n";
	foreach my $l (@lock) {
	    $lock_error_str .= "Clone $l locked by " . $locks{$l}->author->name . " at " . $locks{$l}->timestamp . "\n";
	}

	foreach my $clone (keys %clones) {
	    if (!defined($locks{$clone})) {
		$self->get_CloneLockAdaptor->remove_by_clone_id_version($clone,$clones{$clone});
	    }
	}

	$self->throw($lock_error_str);
    }
}


sub remove_by_slice {
    my ($self,$slice,$author) = @_;

    my %clones = $self->get_clones_versions($slice);

    foreach my $clone (keys %clones) {
	my $lock = $self->get_CloneLockAdaptor->fetch_by_clone_id_version($clone,$clones{$clone});

	if (defined($lock)) {
            if (!defined($lock->author)) {
                $self->throw("Lock " . $lock->id . " " . "doesn't have author attached");
            }
            if (!defined($author)) {
                $self->throw("Author doesn't exist. Can't remove lock");
            }
	    if (
                
		$lock->author->name eq $author->name && 
		$lock->author->email eq $author->email) {
		
		$self->get_CloneLockAdaptor->remove_by_clone_id_version($clone,$clones{$clone});
	    } else {
		$self->warn("Can't unlock clone [$clone]. Owned by author " . $lock->author->name . "\n");
	    }
	} else {
	    $self->warn("Can't unlock clone [$clone]. Lock doesn't exist");
	}
    }
}
	 
	
sub get_clones_versions {
    my ($self,$slice) = @_;

    my @path = @{$slice->get_tiling_path};

    my %clones;
    
    foreach my $p (@path) {
	$clones{$p->component_Seq->clone->id} = $p->component_Seq->clone->version;
    }

    return %clones;

}

sub get_CloneLockAdaptor {
    my ($self) = @_;

    return $self->db->get_CloneLockAdaptor;
}


1;
