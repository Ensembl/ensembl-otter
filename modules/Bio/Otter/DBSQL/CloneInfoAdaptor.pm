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

sub fetch_by_dbID {
    my( $self, $id ) = @_;

    unless ($id) {
        $self->throw("Id must be entered to fetch a CloneInfo object");
    }

    my $sth = $self->prepare(q{
        SELECT clone_info_id
          , clone_id
          , author_id
          , FROM_UNIXTIME(timestamp)
        FROM clone_info
        WHERE clone_info_id = ?
        });
    $sth->execute($id);

    return $self->_obj_from_sth($sth);
}

sub fetch_by_cloneID {
    my( $self, $id ) = @_;

    if (!defined($id)) {
        $self->throw("Id must be entered to fetch a CloneInfo object");
    }

    my $sth = $self->prepare(q{
        SELECT i.clone_info_id
          , i.clone_id
          , i.author_id
          , FROM_UNIXTIME(i.timestamp)
        FROM clone_info i
          , current_clone_info c
        WHERE c.clone_info_id = i.clone_info_id
          AND c.clone_id = ?
        });
    $sth->execute($id);

    return $self->_obj_from_sth($sth);
}

sub _obj_from_sth {
    my( $self, $sth ) = @_;


    if (my $row = $sth->fetch) {
	my $info_id   = $row->[0];
	my $author_id = $row->[2];

	#  Should probably do this all in the sql           
	my $aad = new Bio::Otter::DBSQL::AuthorAdaptor($self->db);
	my $author = $aad->fetch_by_dbID($author_id);


        my @remarks  = $self->db->get_CloneRemarkAdaptor->list_by_clone_info_id($info_id);
        my @keywords = $self->db->get_KeywordAdaptor    ->list_by_clone_info_id($info_id);

	my $cloneinfo = new Bio::Otter::CloneInfo(
            -dbId      => $info_id,
            -clone_id  => $row->[1],
            -author    => $author,
            -timestamp => $row->[3],
            -remark    => \@remarks,
            -keyword   => \@keywords,
            );

	return $cloneinfo;	 	
    } else {
	return;
    }
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

    # Store a new row in the clone_info table and get clone_info_id
    my $sth = $self->prepare(q{
    INSERT INTO clone_info(clone_info_id
          , clone_id
          , author_id
          , timestamp)
    VALUES (NULL,?,?,NOW())
        });
    $sth->execute(
        $cloneinfo->clone_id,
        $cloneinfo->author->dbID,
        );
    my $clone_info_id = $sth->{'mysql_insertid'} or $self->throw("No insert id");

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
    
    # Set as current
    my $set_current = $self->prepare(q{
        REPLACE INTO current_clone_info(clone_id
              , clone_info_id)
        VALUES (?,?)
        });
    $set_current->execute($cloneinfo->clone_id, $clone_info_id);
    
    $cloneinfo->dbID($clone_info_id);
}

1;

	





