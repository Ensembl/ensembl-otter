package Bio::Otter::DBSQL::CloneRemarkAdaptor;

use strict;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::CloneRemark;

use vars qw(@ISA);

@ISA = qw ( Bio::EnsEMBL::DBSQL::BaseAdaptor);

sub _generic_sql_fetch {
    my( $self, $where_clause, @param ) = @_;

    my $sth = $self->prepare(q{
        SELECT clone_remark_id
          , remark
          , clone_info_id
        FROM clone_remark
        } . $where_clause .
        q{ ORDER BY clone_remark_id });
    $sth->execute(@param);

    my @remark;

    while (my $row = $sth->fetch) {
        my $remark = new Bio::Otter::CloneRemark;
        $remark->dbID(         $row->[0]);
        $remark->remark(       $row->[1]);
        $remark->clone_info_id($row->[2]);

        push(@remark,$remark);

    }

    return @remark;
}

sub fetch_by_dbID {
    my ($self, $id) = @_;

    $self->throw("Id must be entered to fetch a CloneRemark object")
        unless $id;

    return $self->_generic_sql_fetch("where clone_remark_id = ? ", $id);
}

sub list_by_clone_info_id {
    my ($self, $id) = @_;

    $self->throw("CloneInfo id must be entered to fetch a CloneRemark object")
        unless $id;

    return $self->_generic_sql_fetch("where clone_info_id = ? ", $id);
}

sub store {
    my $self = shift @_;

    while (my $remark = shift @_) {
	if (!defined($remark)) {
	    $self->throw("Must provide a CloneRemark object to the store method");
	} elsif (! $remark->isa("Bio::Otter::CloneRemark")) {
	    $self->throw("Argument must be a CloneRemark object to the store method.  Currently is [$remark]");
	}

	my $tmp = $self->exists($remark);

	if ($tmp) { 
   	   $remark->dbID($tmp->dbID);
	   return;
	}

	my $sth = $self->prepare(q{
            INSERT INTO clone_remark(clone_remark_id
                  , remark
                  , clone_info_id)
            VALUES (NULL,?,?)
            });
	$sth->execute($remark->remark, $remark->clone_info_id);
        my $clone_remark_id = $sth->{'mysql_insertid'} or $self->throw('No insert id');
	$remark->dbID($clone_remark_id);
    }
    return 1;
}

sub exists {
    my ($self,$remark) = @_;

    if (!defined($remark)) {
        $self->throw("Must provide a CloneRemark object to the exists method");
    } elsif (! $remark->isa("Bio::Otter::CloneRemark")) {
	$self->throw("Argument must be an CloneRemark object to the exists method.  Currently is [$remark]");
    }

    my $remark_text = $remark->remark
        || $self->throw("Can't check if a clone remark exists without remark text");
    my $clone_info_id = $remark->clone_info_id
        || $self->throw("Can't check if a clone remark exists without a clone info id");

    my ($newremark) = $self->_generic_sql_fetch(
        "WHERE remark = ? AND clone_info_id = ? ",
        $remark_text, $clone_info_id,
        );

    return $newremark;
}

1;

	





