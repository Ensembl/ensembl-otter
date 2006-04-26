package Bio::Otter::DBSQL::CurrentTranscriptInfoAdaptor;

use strict;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::Author;

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
		SELECT transcript_info_id,
		       transcript_stable_id
		FROM current_transcript_info }
	. $where_clause;

	my $sth = $self->prepare($sql);
	$sth->execute;

	my @info_id;
	my @transcript_id;

	while (my $ref = $sth->fetchrow_hashref) {
	    push(@info_id,$ref->{transcript_info_id});
	    push(@transcript_id,$ref->{transcript_stable_id});
	}

	return \@transcript_id,\@info_id;
}


=head2 fetch_by_transcript_id

 Title   : fetch_by_transcript_id
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_transcript_id {
	my ($self,$transcript_id) = @_;

	if (!defined($transcript_id)) {
		$self->throw("Transcript id  must be entered to fetch the current transcript info links");
	}

	my ($tran_id,$info_id) = $self->_generic_sql_fetch("where transcript_stable_id = \'$transcript_id\'");

	my @info_id = @$info_id;

	if (scalar(@info_id) > 1) {
	    $self->throw("Something is wrong. There should only be one transcript_info_id for each transcript_id.  We have [@info_id] for info_id [$transcript_id]");
	} elsif (scalar(@info_id) == 1) {
	    return $info_id[0];
	} else {
	    return;
	}

}

sub fetch_by_transcript {
    my ($self, $transcript) = @_;
    
    my $tid = $transcript->dbID
        or $self->throw("Missing dbID");
    my $stable_id = $transcript->stable_id
        or $self->throw("Missing stable_id");
    
    my $find_row = $self->prepare(q{
        SELECT transcript_id
        FROM transcript_stable_id
        WHERE stable_id = ?
        ORDER BY version ASC
        });
    $find_row->execute($stable_id);
    
    my $row;
    for (my $i = 0; my ($this_tid) = $find_row->fetchrow; $i++) {
        if ($this_tid == $tid) {
            $row = $i;
            last;
        }
    }
    $find_row->finish;
    $self->throw("Failed to find row number of transcript('$tid') '$stable_id'")
      unless defined $row;
    
    my $sth = $self->prepare(q{
        SELECT transcript_info_id
        FROM transcript_info
        WHERE transcript_stable_id = ?
        ORDER BY timestamp ASC
        });
    $sth->execute($stable_id);
    
    my $info_id;
    for (my $i = 0; my ($this_info_id) = $sth->fetchrow; $i++) {
        if ($i == $row) {
            $info_id = $this_info_id;
            last;
        }
    }
    $sth->finish;
    if ($info_id) {
        return $info_id;
    } else {
        $self->throw("Failed to get transcript_info_id for transcript '$stable_id' row '$row'");
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
		$self->throw("Transcript info id  must be entered to fetch the current transcript info links");
	}

	my ($transcript_id,$infoid) = $self->_generic_sql_fetch("where transcript_info_id = $info_id");

	my @transcript_id = @$transcript_id;

	if (scalar(@transcript_id) > 1) {
	    $self->throw("Something is wrong. There should only be one transcript_id for each info_id.  We have [@transcript_id] for info_id [$info_id]");
	} elsif (scalar(@transcript_id) == 1) {
	    return $transcript_id[0];
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
	my ($self,$transcript) = @_;
	
	if (!defined($transcript)) {
	    $self->throw("Must provide an AnnotatedTranscript object to the store method");
	} elsif (! $transcript->isa("Bio::Otter::AnnotatedTranscript")) {
	    $self->throw("Argument must be a AnnotatedTranscript object to the store method.  Currently is [$transcript]");
	}

	if (!defined($transcript->transcript_info)) {
	    $self->throw("Transcript must have a transcript_info object to be stored int he current_info table");
	}
	if (!defined($transcript->transcript_info->dbID)) {
	    $self->throw("Transcript info must have a dbID to be stored in the current_info table");
	}
	if (!defined($transcript->stable_id)) {
	    $self->throw("Transcript must have a stable_id to be stored in the current_info table");
	}

	if ($self->exists($transcript)) {
	    return;
	} else {
	    $self->remove_transcript_id($transcript);

	    my $sql = "insert into current_transcript_info(transcript_info_id,transcript_stable_id) values(" . 
		$transcript->transcript_info->dbID . ",\'" . 
		$transcript->stable_id . "\')";

	    my $sth = $self->prepare($sql);
	    my $rv  = $sth->execute();

	    $self->throw("Failed to insert transcript in current_transcript_info table  " . $transcript->stable_id) unless $rv;

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
	my ($self,$transcript) = @_;

	if (!defined($transcript->transcript_info)) {
		$self->throw("Can't check if a current_transcript_info exists without a transcript_info object");
	}

	if (!defined($transcript->transcript_info->dbID)) {
		$self->throw("Can't check if a current_transcript_info exists without a transcript_info dbID");
	}

	if (!defined($transcript->stable_id)) {
		$self->throw("Can't check if a current_transcript_info exists without a transcript stable_id");
	}

	my ($transcript_id,$info_id) = $self->_generic_sql_fetch("where transcript_stable_id = \'" . $transcript->stable_id . "\' and " . 
							   "transcript_info_id = " . $transcript->transcript_info->dbID);


	my @info_id = @$info_id;

	if (scalar(@info_id) >= 1) {
	    return 1;
	} else {
	    return 0 ;
	}


}


sub remove {
    my ($self,$transcript) = @_;

    if (!defined($transcript)) {
	$self->throw("Must provide an AnnotatedTranscript object to the store method");
    } elsif (! $transcript->isa("Bio::Otter::AnnotatedTranscript")) {
	$self->throw("Argument must be a AnnotatedTranscript object to the store method.  Currently is [$transcript]");
    }
    
    if (!defined($transcript->transcript_info)) {
	$self->throw("Transcript must have a transcript_info object to be stored int he current_info table");
    }
    if (!defined($transcript->transcript_info->dbID)) {
	$self->throw("Transcript info must have a dbID to be stored in the current_info table");
    }
    if (!defined($transcript->stable_id)) {
	$self->throw("Transcript must have a stable to be stored in the current_info table");
    }

    my $transcript_id = $transcript->stable_id;
    my $info_id = $transcript->transcript_info->dbID;

    my $sql = "delete from current_transcript_info where transcript_stable_id = \'$transcript_id\' and transcript_info_id = $info_id";

    my $sth = $self->prepare($sql);

    my $rv = $sth->execute;

    $self->throw("Can't delete from current_transcript_info_table") unless $rv;

    return;
}
sub remove_transcript_id {
    my ($self,$transcript) = @_;

    if (!defined($transcript)) {
	$self->throw("Must provide an AnnotatedTranscript object to the store method");
    } elsif (! $transcript->isa("Bio::Otter::AnnotatedTranscript")) {
	$self->throw("Argument must be a AnnotatedTranscript object to the store method.  Currently is [$transcript]");
    }
    
    if (!defined($transcript->transcript_info)) {
	$self->throw("Transcript must have a transcript_info object to be stored int he current_info table");
    }
    if (!defined($transcript->transcript_info->dbID)) {
	$self->throw("Transcript info must have a dbID to be stored in the current_info table");
    }
    if (!defined($transcript->stable_id)) {
	$self->throw("Transcript must have a stable_id to be stored in the current_info table");
    }

    my $transcript_id = $transcript->stable_id;
    my $info_id = $transcript->transcript_info->dbID;

    my $sql = "delete from current_transcript_info where transcript_stable_id = \'$transcript_id\'";

    my $sth = $self->prepare($sql);

    my $rv = $sth->execute;

    $self->throw("Can't delete from current_transcript_info_table") unless $rv;

    return;
}

1;

	





