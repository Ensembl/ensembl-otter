package Bio::Otter::CloneLockBroker;

use vars qw(@ISA);
use strict;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::CloneLock;

# Shouldn't have this
@ISA = qw(Bio::EnsEMBL::DBSQL::BaseAdaptor);


sub client_hostname {
    my( $self, $client_hostname ) = @_;
    
    if ($client_hostname) {
        $self->{'_client_hostname'} = $client_hostname;
    }
    return $self->{'_client_hostname'};
}


### CloneLockBroker should have an Author and a CloneLockAdaptor attached
### so it doesn't need to inherit from BaseAdaptor

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

    my $clone_list = $self->Clone_listref_from_Slice($slice);
    my $aptr = $self->get_CloneLockAdaptor;

    my( @locks );
    foreach my $clone (@$clone_list) {
	my $lock = $aptr->fetch_by_clone_id($clone->dbID)   
            or $self->throw(sprintf "Clone [%s] not locked\n", $clone->id);
	unless ($lock->author->name eq $author->name) {
	    $self->throw("Author [" . $author->name . "] doesn't own lock for $clone");
        }
        push(@locks, $lock);
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

    my $clone_list = $self->Clone_listref_from_Slice($slice);
    my $aptr       = $self->get_CloneLockAdaptor;

    foreach my $clone (@$clone_list) {
        $self->throw("Clone '". $clone->embl_id .'.'. $clone->embl_version ."' is locked\n")
            if $aptr->fetch_by_clone_id($clone->dbID);
    }
    return 1;
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

    my $clone_list = $self->Clone_listref_from_Slice($slice);
    my $aptr       = $self->get_CloneLockAdaptor;

    my( @new,               # locks we manange to create
        @existing,          # locks that already existed
        %existing_clone,    # clones that had locks existing (for nice error message)
         );
    foreach my $clone (@$clone_list) {
        my $clone_id = $clone->dbID
            or $self->throw('Clone does not have dbID set');
	my $lock = Bio::Otter::CloneLock->new(
            -author     => $author, 
	    -clone_id   => $clone_id,
            -hostname   => $self->client_hostname,
            );
	eval {
	    $self->get_CloneLockAdaptor->store($lock); 
	};
	if ($@) {
	    my $exlock = $self->get_CloneLockAdaptor->fetch_by_clone_id($clone_id);
	    push(@existing, $exlock);
            $existing_clone{$clone_id} = $clone;
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
        my $lock_error_str = "Can't lock clones because some are already locked:\n";
	foreach my $lock (@existing) {
            my $clone = $existing_clone{$lock->clone_id};
	    $lock_error_str .= sprintf "  '%s' has been locked by '%s' since %s\n",
                $clone->id, $lock->author->name, scalar localtime($lock->timestamp);
	}
	$self->throw($lock_error_str);
    }
}


sub remove_by_slice {
    my ($self,$slice,$author) = @_;

    my $clone_list = $self->Clone_listref_from_Slice($slice);
    my $aptr       = $self->get_CloneLockAdaptor;

    foreach my $clone (@$clone_list) {
	if (my $lock = $self->get_CloneLockAdaptor->fetch_by_clone_id($clone->dbID)) {
	    unless ($lock->author->equals($author)) {
	        $self->throw("Author [" . $author->name . "] doesn't own lock for $clone");
            }
            $aptr->remove($lock);
	} else {
	    $self->warn("Can't unlock clone [$clone]. Lock doesn't exist");
	}
    }
}
	 

sub Clone_listref_from_Slice {
    my( $self, $slice ) = @_;
    
    my $clone_list = [];
    my $path = $slice->get_tiling_path;
    foreach my $tile (@$path) {
        push(@$clone_list, $tile->component_Seq->clone);
    }
    return $clone_list;
}

sub get_CloneLockAdaptor {
    my ($self) = @_;

    return $self->db->get_CloneLockAdaptor;
}


1;
