package Bio::Vega::DBSQL::ContigInfoAdaptor;

use strict;
use Bio::Vega::ContigInfo;

use base qw ( Bio::EnsEMBL::DBSQL::BaseAdaptor);

sub fetch_by_dbID {
    my( $self, $id ) = @_;

    unless ($id) {
        $self->throw("Id must be entered to fetch a ContigInfo object");
    }

    my $sth = $self->prepare(q{
        SELECT contig_info_id
          , seq_region_id
          , author_id
          , FROM_UNIXTIME(created_date)
        FROM contig_info
        WHERE contig_info_id = ?
        });
    $sth->execute($id);

    return $self->_obj_from_sth($sth);
}

sub fetch_by_seq_region_id {
    my( $self, $id ) = @_;

    if (!defined($id)) {
        $self->throw("Id must be entered to fetch a ContigInfo object");
    }

    my $sth = $self->prepare(q{
        SELECT contig_info_id
          , seq_region_id
          , author_id
          , FROM_UNIXTIME(created_date)
        FROM contig_info
        WHERE seq_region_id = ?
          AND is_current = 1
        });
    $sth->execute($id);

    return $self->_obj_from_sth($sth);
}

sub store {
    my( $self,$contiginfo ) = @_;
    unless ($contiginfo) {
        $self->throw("Must provide a ContigInfo object to the store method");
    } elsif (! $contiginfo->isa("Bio::Vega::ContigInfo")) {
        $self->throw("Argument '$contiginfo' to the store method must be a ContigInfo object.");
    }
    my $slice = $contiginfo->slice
        || $self->throw('Cannot store contig_info without attached slice');
	 my $sa=$self->db->get_SliceAdaptor();
	 my $seq_region_id = $sa->get_seq_region_id($slice);
	 # if any clone_info exists for the same seq_region_id then make them non-current
	 my $sth=$self->prepare(q{
    UPDATE contig_info
    SET is_current = 0
    WHERE seq_region_id = ?
        });
	 $sth->execute($seq_region_id);
    my $authad = $self->db->get_AuthorAdaptor;
    $authad->store($contiginfo->author);
    # Store a new row in the clone_info table and get clone_info_id
    $sth = $self->prepare(q{
    INSERT INTO contig_info(
           seq_region_id
          , author_id
          , created_date
          , is_current)
    VALUES (?,?,NOW(),1)
        });
	 my $author=$contiginfo->author;
	 my $author_id=$author->dbID;
    $sth->execute(
						$seq_region_id,
						$author_id,
					  );
    my $contig_info_id = $sth->{'mysql_insertid'} or $self->throw("No insert id");
    $contiginfo->dbID($contig_info_id);
	 my $aa=$self->db->get_AttributeAdaptor;
	 $aa->store_on_ContigInfo($contiginfo,$contiginfo->get_all_Attributes);
}

1;

__END__

=head1 NAME - Bio::Vega::DBSQL::ContigInfoAdaptor.pm

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk

	





