package Bio::Otter::DBSQL::CurrentGeneInfoAdaptor;

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
		SELECT gene_info_id,
		       gene_stable_id
		FROM current_gene_info }
	. $where_clause;

	my $sth = $self->prepare($sql);
	$sth->execute;

	my @info_id;
	my @gene_id;

	while (my $ref = $sth->fetchrow_hashref) {
	    push(@info_id,$ref->{gene_info_id});
	    push(@gene_id,$ref->{gene_stable_id});
	}

	return \@gene_id,\@info_id;
}


=head2 fetch_by_gene_id

 Title   : fetch_by_gene_id
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_gene_id {
	my ($self,$gene_id) = @_;

	if (!defined($gene_id)) {
		$self->throw("Gene id  must be entered to fetch the current gene info links");
	}

	my ($gid,$info_id) = $self->_generic_sql_fetch("where gene_stable_id = \'$gene_id\'");
        #print "GENEID $gene_id\n";
	my @info_id = @$info_id;
        #print "Info " . @info_id . "\n";
	if (scalar(@info_id) > 1) {
	    $self->throw("Something is wrong. There should only be one gene_info_id for each gene_id.  We have [@info_id] for info_id [$gene_id]");
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
		$self->throw("Gene info id  must be entered to fetch the current gene info links");
	}

	my ($gene_id,$infoid) = $self->_generic_sql_fetch("where gene_info_id = $info_id");

	my @gene_id = @$gene_id;

	if (scalar(@gene_id) > 1) {
	    $self->throw("Something is wrong. There should only be one gene_id for each info_id.  We have [@gene_id] for info_id [$info_id]");
	} elsif (scalar(@gene_id) == 1) {
	    return $gene_id[0];
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
	my ($self,$gene) = @_;
	
	if (!defined($gene)) {
	    $self->throw("Must provide an AnnotatedGene object to the store method");
	} elsif (! $gene->isa("Bio::Otter::AnnotatedGene")) {
	    $self->throw("Argument must be a AnnotatedGene object to the store method.  Currently is [$gene]");
	}

	if (!defined($gene->gene_info)) {
	    $self->throw("Gene must have a gene_info object to be stored int he current_info table");
	}
	if (!defined($gene->gene_info->dbID)) {
	    $self->throw("Gene info must have a dbID to be stored in the current_info table");
	}
	if (!defined($gene->stable_id)) {
	    $self->throw("Gene must have a stable_id to be stored in the current_info table");
	}

	if ($self->exists($gene)) {
	    return;
	} else {
	    $self->remove_gene_id($gene);

	    my $sql = "insert into current_gene_info(gene_info_id,gene_stable_id) values(" . 
		$gene->gene_info->dbID . ",\'" . 
		$gene->stable_id . "\')";

	    my $sth = $self->prepare($sql);
	    my $rv  = $sth->execute();

	    $self->throw("Failed to insert gene in current_gene_info table  " . $gene->stable_id) unless $rv;

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
	my ($self,$gene) = @_;

	if (!defined($gene->gene_info)) {
		$self->throw("Can't check if a current_gene_info exists without a gene_info object");
	}

	if (!defined($gene->gene_info->dbID)) {
		$self->throw("Can't check if a current_gene_info exists without a gene_info dbID");
	}

	if (!defined($gene->stable_id)) {
		$self->throw("Can't check if a current_gene_info exists without a gene stable_id");
	}

	my ($gene_id,$info_id) = $self->_generic_sql_fetch("where gene_stable_id = \'" . $gene->stable_id . "\' and " . 
							   "gene_info_id = " . $gene->gene_info->dbID);


	my @info_id = @$info_id;

	if (scalar(@info_id) >= 1) {
	    return 1;
	} else {
	    return 0 ;
	}


}


sub remove {
    my ($self,$gene) = @_;

    if (!defined($gene)) {
	$self->throw("Must provide an AnnotatedGene object to the store method");
    } elsif (! $gene->isa("Bio::Otter::AnnotatedGene")) {
	$self->throw("Argument must be a AnnotatedGene object to the store method.  Currently is [$gene]");
    }
    
    if (!defined($gene->gene_info)) {
	$self->throw("Gene must have a gene_info object to be stored int he current_info table");
    }
    if (!defined($gene->gene_info->dbID)) {
	$self->throw("Gene info must have a dbID to be stored in the current_info table");
    }
    if (!defined($gene->stable)) {
	$self->throw("Gene must have a stable to be stored in the current_info table");
    }

    my $gene_id = $gene->stable;
    my $info_id = $gene->gene_info->dbID;

    my $sql = "delete from current_gene_info where gene_stable_id = \'$gene_id\' and gene_info_id = $info_id";

    my $sth = $self->prepare($sql);

    my $rv = $sth->execute;

    $self->throw("Can't delete from current_gene_info_table") unless $rv;

    return;
}
sub remove_gene_id {
    my ($self,$gene) = @_;

    if (!defined($gene)) {
	$self->throw("Must provide an AnnotatedGene object to the store method");
    } elsif (! $gene->isa("Bio::Otter::AnnotatedGene")) {
	$self->throw("Argument must be a AnnotatedGene object to the store method.  Currently is [$gene]");
    }
    
    if (!defined($gene->gene_info)) {
	$self->throw("Gene must have a gene_info object to be stored int he current_info table");
    }
    if (!defined($gene->gene_info->dbID)) {
	$self->throw("Gene info must have a dbID to be stored in the current_info table");
    }
    if (!defined($gene->stable_id)) {
	$self->throw("Gene must have a stable_id to be stored in the current_info table");
    }

    my $gene_id = $gene->stable_id;
    my $info_id = $gene->gene_info->dbID;

    my $sql = "delete from current_gene_info where gene_stable_id = \'$gene_id\'";

    my $sth = $self->prepare($sql);

    my $rv = $sth->execute;

    $self->throw("Can't delete from current_gene_info_table") unless $rv;

    return;
}

1;

	





