package Bio::Otter::DBSQL::CloneInfoAdaptor;

use strict;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::DBSQL::AuthorAdaptor;
use Bio::Otter::CloneInfo;
use Bio::Otter::CloneRemark;
use Bio::Otter::Keyword;

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
		SELECT clone_info_id,
		       clone_id,
                       author_id,
                       timestamp,
                       is_active,
                       database_source
		FROM clone_info }
	. $where_clause;

	my $sth = $self->prepare($sql);
	$sth->execute;

	if (my $ref = $sth->fetchrow_hashref) {
		my $info_id   = $ref->{clone_info_id};
		my $clone_id  = $ref->{clone_id};
		my $author_id = $ref->{author_id};
		my $timestamp = $ref->{timestamp};
		my $is_active = $ref->{is_active};
		my $source    = $ref->{database_source};

		#  Should probably do this all in the sql           
		my $aad = new Bio::Otter::DBSQL::AuthorAdaptor($self->db);
		my $author = $aad->fetch_by_dbID($author_id);


                my @remarks  = $self->db->get_CloneRemarkAdaptor->list_by_clone_info_id($ref->{'clone_info_id'});
                my @keywords = $self->db->get_KeywordAdaptor->list_by_clone_info_id($ref->{'clone_info_id'});

		my $cloneinfo = new Bio::Otter::CloneInfo(-dbId      => $info_id,
                                                          -clone_id  => $clone_id,
                                                          -author    => $author,
                                                          -timestamp => $timestamp,
                                                          -is_active => $is_active,
                                                          -remark    => \@remarks,
                                                          -keyword   => \@keywords,
                                                          -source    => $source);
        
		return $cloneinfo;	 	

	} else {
		return;
	}
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

    unless ($id) {
        $self->throw("Id must be entered to fetch a CloneInfo object");
    }

    my $cloneinfo = $self->_generic_sql_fetch("where clone_info_id = $id");

    return $cloneinfo;
}

=head2 fetch_by_cloneID

 Title   : fetch_by_cloneID
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_cloneID {
    my ($self,$id) = @_;

    if (!defined($id)) {
        $self->throw("Id must be entered to fetch a CloneInfo object");
    }

    my $cloneinfo = $self->_generic_sql_fetch("where clone_id = $id");

    return $cloneinfo;
}


sub store {
    my( $self, $cloneinfo ) = @_;

    unless ($cloneinfo) {
        $self->throw("Must provide a CloneInfo object to the store method");
    } elsif (! $cloneinfo->isa("Bio::Otter::CloneInfo")) {
        $self->throw("Argument '$cloneinfo' to the store method must be a CloneInfo object.");
    }
    my $clone_id = $cloneinfo->clone_id
        || $self->throw('Cannot store clone_info without clone_id');

    my $authad = new Bio::Otter::DBSQL::AuthorAdaptor($self->db);
    $authad->store($cloneinfo->author);


    my $update_sth = $self->prepare(q{
        UPDATE clone_info
        SET is_active = 'false'
        WHERE clone_id = ?
        });
    $update_sth->execute($cloneinfo->clone_id);

    my $sth = $self->prepare(q{
    INSERT INTO clone_info(clone_info_id
          , clone_id
          , author_id
          , timestamp
          , is_active
          , database_source)
    VALUES (NULL,?,?,NOW(),'true',?)
        });
    $sth->execute(
        $cloneinfo->clone_id,
        $cloneinfo->author->dbID,
        $cloneinfo->source,
        );
    my $clone_info_id = $sth->{'mysql_insertid'} or $self->throw("No insert id");
    $cloneinfo->dbID($clone_info_id);

    # Store Keywords
    if (my @keywords = $cloneinfo->keyword) {
        my $key_aptr = $self->db->get_KeywordAdaptor;
        foreach my $keyword (@keywords) {
            $keyword->clone_info_id($clone_info_id);
            $key_aptr->store($keyword);
        }
    }

    # Store Remarks
    if (my @remarks = $cloneinfo->remark) {
        my $rem_aptr = $self->db->get_CloneRemarkAdaptor;
        foreach my $remark (@remarks) {
            $remark->clone_info_id($clone_info_id);
            $rem_aptr->store($remark);
        }
    }
}

1;

	





