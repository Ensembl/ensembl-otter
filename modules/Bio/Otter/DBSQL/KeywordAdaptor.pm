package Bio::Otter::DBSQL::KeywordAdaptor;

use strict;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::Keyword;

use vars qw(@ISA);

@ISA = qw ( Bio::EnsEMBL::DBSQL::BaseAdaptor);

sub _generic_sql_fetch {
	my( $self, $where_clause ) = @_;

	my $sql = q{
		SELECT k.keyword_id,
		       k.keyword_name,
                       ck.clone_info_id
		FROM keyword k,clone_info_keyword ck }
	. $where_clause;

	#print $sql . "\n";

	my $sth = $self->prepare($sql);
	$sth->execute;

	my @obj;

	while (my $ref = $sth->fetchrow_hashref) {
	    my $obj = new Bio::Otter::Keyword;
	    $obj->dbID           ($ref->{'keyword_id'});
	    $obj->name           ($ref->{'keyword_name'});
	    $obj->clone_info_id  ($ref->{'clone_info_id'});
	    
	    push(@obj,$obj);
	}

	return @obj;
}

sub fetch_by_dbID {
    my ($self,$id) = @_;
    
    if (!defined($id)) {
	$self->throw("Id must be entered to fetch a keyword object");
    }
    
    my @obj = $self->_generic_sql_fetch("where ck.keyword_id = k.keyword_id and k.keyword_id = $id");
    
    return @obj;
}

sub list_by_clone_info_id {
    my ($self,$id) = @_;
    
    if (!defined($id)) {
	$self->throw("Id must be entered to fetch a keyword object");
    }
    
    my @obj = $self->_generic_sql_fetch("where ck.keyword_id = k.keyword_id and ck.clone_info_id = $id");
    
    return @obj;
}

sub list_by_name {
    my ($self,$name) = @_;
    
    if (!defined($name)) {
	$self->throw("Name must be entered to fetch keyword objects");
    }
    
    my @obj = $self->_generic_sql_fetch("where ck.keyword_id = k.keyword_id and k.keyword_name = \'$name\'");
    
    return @obj;
}

sub get_all_Keyword_names {
    my ($self) = @_;

    my $sql = "SELECT distinct keyword_name from keyword";

    my $sth = $self->prepare($sql);
    $sth->execute;

    my @names;

    while (my $ref = $sth->fetchrow_hashref) {
	push(@names,$ref->{keyword_name});
    }

    return @names;
}

sub store {
    my $self = shift @_;
	
    while (my $keyword = shift @_) {
	if (!defined($keyword)) {
	    $self->throw("Must provide a keyword object to the store method");
	} elsif (! $keyword->isa("Bio::Otter::Keyword")) {
	    $self->throw("Argument must be a keyword object to the store method.  Currently is [$keyword]");
	}

	if (!defined($keyword->clone_info_id)) {
	    $self->throw("Must provide a clone_info_id value to the keyword object when trying to store");
	}
	
	my ($keyword_id, $is_stored) = $self->exists($keyword);
	
	next if $is_stored;
	
	unless ($keyword_id) {
	    my $sth = $self->prepare(q{
                INSERT INTO keyword(keyword_id, keyword_name)
                VALUES (NULL, ?)
                });
	    $sth->execute($keyword->name);
	    $keyword_id = $sth->{'mysql_insertid'} or $self->throw('No insert id');
	}
	$keyword->dbID($keyword_id);
	
	# Insert link to clone_info
	my $sth = $self->prepare(q{
            INSERT INTO clone_info_keyword(clone_info_id, keyword_id)
            VALUES(?,?)
            });
	$sth->execute($keyword->clone_info_id, $keyword_id);
    }
}

sub exists {
    my ($self, $keyword) = @_;

    if (!defined($keyword)) {
	$self->throw("Must provide a keyword object to the exists method");
    } elsif (! $keyword->isa("Bio::Otter::Keyword")) {
	$self->throw("Argument must be a keyword object to the exists method.  Currently is [$keyword]");
    }

    my $keyword_name = $keyword->name
        || $self->throw("Can't check if a keyword exists without a name");

    # Get the id for this keyword if it is in the db.
    my $sth = $self->prepare(q{ SELECT keyword_id FROM keyword WHERE keyword_name = ? });
    $sth->execute($keyword_name);
    my ($keyword_id) = $sth->fetchrow;
    
    if ($keyword_id) {
        # They keyword is in the database, but is it linked to the clone_info?
        if (my $clone_info_id = $keyword->clone_info_id) {
	    my $sth = $self->prepare(q{
                SELECT count(*)
                FROM clone_info_keyword
                WHERE keyword_id = ?
                  AND clone_info_id = ?
                });
	    $sth->execute($keyword_id, $clone_info_id);
            my ($count) = $sth->fetchrow;
	    if ($count) {
                # keyword is in the database, and is already linked to the clone_info
                return($keyword_id, 1);
	    }
        }
    }
    
    # keyword_id will be undef if it is not in the database
    return($keyword_id);
}

1;

	





