package Bio::Otter::DBSQL::CurrentCloneInfoAdaptor;

use strict;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::Author;

use vars qw(@ISA);

@ISA = qw ( Bio::EnsEMBL::DBSQL::BaseAdaptor);

# new is inherited

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
		SELECT clone_info_id,
		       clone_id,
                       clone_version 
		FROM current_clone_info }
	. $where_clause;

	my $sth = $self->prepare($sql);
	$sth->execute;

	my @info_id;
	my @accession;
	my @version;

	while (my $ref = $sth->fetchrow_hashref) {
	    push(@info_id,$ref->{clone_info_id});
	    push(@accession,$ref->{clone_id});
	    push(@version,  $ref->{clone_version});
	}

	return \@accession,\@version,\@info_id;
}


=head2 fetch_by_accession_version

 Title   : fetch_by_accession_version
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_accession_version {
	my ($self,$accession,$version) = @_;

	if (!defined($accession)) {
		$self->throw("Accession  must be entered to fetch the current clone info links");
	}
	if (!defined($version)) {
		$self->throw("Version must be entered to fetch the current clone info links");
	}

	my ($acc,$ver,$info_id) = $self->_generic_sql_fetch("where clone_id = \'$accession\' and clone_version = $version");

	my @info_id = @$info_id;

	if (scalar(@info_id) > 1) {
	    $self->throw("Something is wrong. There should only be one clone_info_id for each accession and version. We have [@info_id] for accession [$accession] and version [$version]");
	} elsif (scalar(@info_id) == 1) {
	    return $info_id[0];
	} else {
	    return;
	}

}

=head2 fetch_by_info_id

 Title   : fetch_by_info_id
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_info_id {
	my ($self,$info_id) = @_;

	if (!defined($info_id)) {
		$self->throw("Clone info id  must be entered to fetch the current clone info links");
	}

	my ($accession,$version,$infoid) = $self->_generic_sql_fetch("where clone_info_id = $info_id");

	my @accession = @$accession;
	my @version   = @$version;

	if (scalar(@accession) > 1) {
	    $self->throw("Something is wrong. There should only be one accession,version for each info_id.  We have [\@accession][\@version] for info_id [$info_id]");

	} elsif (scalar(@accession) == 1 && scalar(@version) == 1) {
	    return $accession[0],$version[0];
	} else {
	    return;
	}
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
	my ($self,$clone) = @_;
	
	if (!defined($clone)) {
	    $self->throw("Must provide an AnnotatedClone object to the store method");
	} elsif (! $clone->isa("Bio::Otter::AnnotatedClone")) {
	    $self->throw("Argument must be a AnnotatedClone object to the store method.  Currently is [$clone]");
	}

	if (!defined($clone->clone_info)) {
	    $self->throw("Clone must have a clone_info object to be stored int he current_info table");
	}
	if (!defined($clone->clone_info->dbID)) {
	    $self->throw("Clone info must have a dbID to be stored in the current_info table");
	}
	if (!defined($clone->embl_id)) {
	    $self->throw("Clone must have an accession to be stored in the current_info table");
	}
	if (!defined($clone->embl_version)) {
	    $self->throw("Clone must have a version to be stored in the current_info table");
	}

	if ($self->exists($clone)) {
	    return;
	} else {
	    $self->remove_accession_version($clone);

	    my $sql = "insert into current_clone_info(clone_info_id,clone_id,clone_version) values(" . 
		$clone->clone_info->dbID . ",\'" . 
		$clone->embl_id . "\'," . 
                $clone->embl_version . ")";

	    my $sth = $self->prepare($sql);
	    my $rv  = $sth->execute();

	    $self->throw("Failed to insert clone in current_clone_info table  " . $clone->id . " " . $clone->embl_version) unless $rv;

	}
    
}

=head2 exists

 Title   : exists
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub exists {
	my ($self,$clone) = @_;

	if (!defined($clone->clone_info)) {
		$self->throw("Can't check if a current_clone_info exists without a clone_info object");
	}

	if (!defined($clone->clone_info->dbID)) {
		$self->throw("Can't check if a current_clone_info exists without a clone_info dbID");
	}

	if (!defined($clone->id)) {
		$self->throw("Can't check if a current_clone_info exists without a clone name");
	}
	if (!defined($clone->embl_version)) {
		$self->throw("Can't check if a current_clone_info exists without a clone version");
	}

	my ($accession,$version,$info_id) = $self->_generic_sql_fetch("where clone_id = \'" . $clone->id  . "\' and clone_version = " . $clone->embl_version . " and " . "clone_info_id = " . $clone->clone_info->dbID);


	my @info_id = @$info_id;

	if (scalar(@info_id) >= 1) {
	    return 1;
	} else {
	    return 0 ;
	}


}


sub remove {
    my ($self,$clone) = @_;

    if (!defined($clone)) {
	$self->throw("Must provide an AnnotatedClone object to the remove method");
    } elsif (! $clone->isa("Bio::Otter::AnnotatedClone")) {
	$self->throw("Argument must be a AnnotatedClone object to the remove method.  Currently is [$clone]");
    }
    
    if (!defined($clone->clone_info)) {
	$self->throw("Clone must have a clone_info object to be removed from the current_info table");
    }
    if (!defined($clone->clone_info->dbID)) {
	$self->throw("Clone info must have a dbID to be removed from  the current_info table");
    }
    if (!defined($clone->id)) {
	$self->throw("Clone must have a name to be removed from  the current_info table");
    }
    if (!defined($clone->embl_version)) {
	$self->throw("Clone must have a versionto be removed from  the current_info table");
    }

    my $name    = $clone->id;
    my $info_id = $clone->clone_info->dbID;

    my $sql = "delete from current_clone_info where clone_id = \'$name\' and clone_info_id = $info_id";

    my $sth = $self->prepare($sql);

    my $rv = $sth->execute;

    $self->throw("Can't delete from current_clone_info_table") unless $rv;

    return;
}

sub remove_accession_version {
    my ($self,$clone) = @_;

    if (!defined($clone)) {
	$self->throw("Must provide an AnnotatedClone object to the remove method");
    } elsif (! $clone->isa("Bio::Otter::AnnotatedClone")) {
	$self->throw("Argument must be a AnnotatedClone object to the store method.  Currently is [$clone]");
    }
    
    if (!defined($clone->clone_info)) {
	$self->throw("Clone must have a clone_info object to be removed from the current_info table");
    }
    if (!defined($clone->clone_info->dbID)) {
	$self->throw("Clone info must have a dbID to be removed from the current_info table");
    }
    if (!defined($clone->id)) {
	$self->throw("Clone must have a name to be removed from the current_info table");
    }
    if (!defined($clone->embl_version)) {
	$self->throw("Clone must have a embl_version to be removed from the current_info table");
    }

    my $name    = $clone->id;
    my $version = $clone->embl_version;
    my $info_id = $clone->clone_info->dbID;

    my $sql = "delete from current_clone_info where clone_id = \'$name\' and clone_version = $version";

    my $sth = $self->prepare($sql);

    my $rv = $sth->execute;

    $self->throw("Can't delete from current_clone_info_table") unless $rv;

    return;
}

1;

	





