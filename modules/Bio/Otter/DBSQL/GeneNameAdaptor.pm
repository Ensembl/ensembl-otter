package Bio::Otter::DBSQL::GeneNameAdaptor;

use strict;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::GeneName;

use vars qw(@ISA);

@ISA = qw ( Bio::EnsEMBL::DBSQL::BaseAdaptor);

# new is inherieted

=head2 _generic_sql_fetch

 Title   : _generic_sql_fetch
 Usage   : $self->_generic_sql_fetch("where gene_name = ?", [$var1])
 Function: return a list ref of GeneName objs that match a criterion.
 Example : 
 Returns : array ref '[]' of GeneName objs
 Args    : optional "where clause" and bind variables for that clause []


=cut

sub _generic_sql_fetch {
	my( $self, $where_clause, $bind ) = @_;

        my @bind = ($bind ? @$bind : ());

	my $sql = q{
		SELECT gene_name_id,
		       name,
		       gene_info_id
		FROM gene_name }
	. ( $where_clause ? $where_clause : '' );

	my $sth = $self->prepare($sql);
	$sth->execute(@bind);

        my $names = [];

        while (my $ref = $sth->fetchrow_hashref)  {
            my $obj = new Bio::Otter::GeneName;
            $obj->dbID($ref->{gene_name_id});
            $obj->name($ref->{name});
            $obj->gene_info_id($ref->{gene_info_id});
            push(@$names,$obj);
        }

        return $names;
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
        $self->throw("Id must be entered to fetch a GeneName object");
    }

    my $geneNames = $self->_generic_sql_fetch("where gene_name_id = ?", [$id]);

    return @$geneNames ? $geneNames->[0] : undef; # not sure this is right, previous behaviour though
}

sub fetch_all {
    my ($self) = @_;
    return $self->_generic_sql_fetch();
}

=head2 fetch_by_name

 Title   : fetch_by_name
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut


sub fetch_by_name {
    my ($self,$name) = @_;
    
    if (!defined($name)) {
        $self->throw("Name must be entered to fetch a GeneName object");
    }

    return $self->_generic_sql_fetch("where name = ? ",[$name]);
}


=head2 fetch_by_gene_info_id

 Title   : fetch_by_gene_info_id
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_gene_info_id{
   my ($self,$id) = @_;

   if (!defined($id)) {
       $self->throw("GeneInfo id must be entered to fetch a GeneName object");
	}

   my $geneNames = $self->_generic_sql_fetch("where gene_info_id = ?",[$id]);

   return @$geneNames ? $geneNames->[0] : undef; # not sure this is right, previous behaviour though

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
    my ($self,$obj) = @_;

    if (!defined($obj)) {
	$self->throw("Must provide a GeneName object to the store method");
    } elsif (! $obj->isa("Bio::Otter::GeneName")) {
	$self->throw("Argument must be a GeneName object to the store method.  Currently is [$obj]");
	}

    my $tmp = $self->exists($obj);

    if (defined($tmp)) {
	$obj->dbID($tmp->dbID);
	return;
    }

    my $sql = "insert into gene_name(gene_name_id,name,gene_info_id) values (null,\'" . 
	$obj->name . "\',".
	$obj->gene_info_id . ")";

    my $sth = $self->prepare($sql);
    my $rv = $sth->execute();

    $self->throw("Failed to insert gene_name " . $obj->name) unless $rv;

    $sth = $self->prepare("select last_insert_id()");
    my $res = $sth->execute;
    my $row = $sth->fetchrow_hashref;
    $sth->finish;
	
    $obj->dbID($row->{'last_insert_id()'});
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
    my ($self,$obj) = @_;

    if (!defined($obj)) {
	$self->throw("Must provide a GeneName object to the exists method");
    } elsif (! $obj->isa("Bio::Otter::GeneName")) {
	$self->throw("Argument must be a GeneName object to the exists method.  Currently is [$obj]");
    }

    if (!defined($obj->name)) {
	$self->throw("Can't check if a GeneName exists without a name");
    }
    if (!defined($obj->gene_info_id)) {
	$self->throw("Can't check if a GeneName exists without a GeneInfo id");
    }

    my $geneNames = $self->_generic_sql_fetch("where name = ? and gene_info_id = ?", [$obj->name, $obj->gene_info_id]);

    return @$geneNames ? $geneNames->[0] : undef; # not sure this is right, previous behaviour though

}
1;

	





