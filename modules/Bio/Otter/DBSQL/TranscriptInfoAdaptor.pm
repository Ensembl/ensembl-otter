package Bio::Otter::DBSQL::TranscriptInfoAdaptor;

use strict;
use Bio::EnsEMBL::DBSQL::BaseAdaptor;
use Bio::Otter::TranscriptInfo;

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

	my $sql = q{SELECT transcript_info_id,
		    transcript_stable_id,
		    name,
		    transcript_class_id,
		    cds_start_not_found,
		    cds_end_not_found,
		    mRNA_start_not_found,
		    mRNA_end_not_found,
		    author_id,
		    timestamp 
			FROM transcript_info } . $where_clause;

	my $sth = $self->prepare($sql);
	$sth->execute();

	my %class_hash;

	my @out;

	while ( my $ref = $sth->fetchrow_hashref) {

	    my $author   = $self->db->get_AuthorAdaptor->fetch_by_dbID         ($ref->{'author_id'});
	    my $class    = $self->db->get_TranscriptClassAdaptor->fetch_by_dbID($ref->{'transcript_class_id'});
	    my @remarks  = $self->db->get_TranscriptRemarkAdaptor->list_by_transcript_info_id($ref->{'transcript_info_id'});
	    my @evidence = $self->db->get_EvidenceAdaptor->list_by_transcript_info_id($ref->{'transcript_info_id'});
 	    if (!defined($author)) {
		$self->throw("Can't get TranscriptInfo as invalid author id [" . $ref->{'author_id'} . "]");
		
	    }
 	    if (!defined($class)) {
		$self->throw("Can't get TranscriptInfo as invalid class id  [" . $ref->{'transcript_class_id'} . "]");
	    }

	    my $ti = Bio::Otter::TranscriptInfo->new( 
		-dbId                 => $ref->{'transcript_info_id'},
		-stable_id => $ref->{'transcript_stable_id'},
		-name                 => $ref->{'name'},
		-class                => $class,
		-cds_start_not_found  => $ref->{'cds_start_not_found'},
		-cds_end_not_found    => $ref->{'cds_end_not_found'},
		-mRNA_start_not_found => $ref->{'mRNA_start_not_found'},
		-mRNA_end_not_found   => $ref->{'mRNA_end_not_found'},
                -author               => $author,
		-remark               => \@remarks,
                -evidence             => \@evidence,
		-timestamp            => $ref->{'timestamp'}
						      );

	    push(@out,$ti);

	}
	
	return @out;
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
		$self->throw("Id must be entered to fetch a TranscriptInfo object");
	}

	my ($ti) = $self->_generic_sql_fetch("where transcript_info_id = $id");
	
	return $ti;
}


=head2 fetch_by_stable_id

 Title   : fetch_by_stable_id
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_stable_id {
   my ($self,$id) = @_;

    $self->throw("this method does not work");
   #if (!defined($id)) {
   #    $self->throw("Stable id must be entered to fetch a TranscriptInfo object");
   #}
   #
   #my ($ti) = $self->_generic_sql_fetch("where transcript_stable_id = \'$id\'");
   #
   #return $ti;
   
}

=head2 list_by_author

 Title   : list_by_author
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub list_by_author {
   my ($self,$author) = @_;


   if (!defined($author)) {
       $self->throw("Author must be entered to fetch a TranscriptInfo object");
   }
   
   if ($author->isa("Bio::Otter::Author")) {
       $self->throw("Object must be an Bio::Otter::Author object to list by author.  Currently [" . $author . "]");
   }

   if (!defined($author->dbID)) {
       #Should do something here
   }
   
   my @ti = $self->_generic_sql_fetch("where author_id = " . $author->dbID);
   
   return @ti;
   
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
    my ($self,$traninfo) = @_;

    if (!defined($traninfo)) {
        $self->throw("Must provide a TranscriptInfo object to the store method");
    } elsif (! $traninfo->isa("Bio::Otter::TranscriptInfo")) {
        $self->throw("Argument must be a TranscriptInfo object to the store method.  Currently is [$traninfo]");
    }

    printf STDERR "About to store TranscriptInfo '%s'\n", $traninfo->name;

    # Now lets store the author and class info - adds in the dbID if it doesn't exist
    $self->db->get_AuthorAdaptor->store         ($traninfo->author);
    $self->db->get_TranscriptClassAdaptor->store($traninfo->class);

    #print "Author dbid is " . $traninfo->author->dbID . "\n";
    #print "Class dbid is " . $traninfo->class->dbID . "\n";

    my $sth = $self->prepare(q{
        INSERT INTO transcript_info (transcript_info_id
              , transcript_stable_id
              , name
              , transcript_class_id
              , cds_start_not_found
              , cds_end_not_found
              , mRNA_start_not_found
              , mRNA_end_not_found
              , author_id
              , timestamp)
        VALUES (NULL,?,?,?,?,?,?,?,?,NOW())
        });
    $sth->execute(
        $traninfo->transcript_stable_id,
        $traninfo->name,
        $traninfo->class->dbID,
        $traninfo->cds_start_not_found  ? 'true' : 'false',
        $traninfo->cds_end_not_found    ? 'true' : 'false',
        $traninfo->mRNA_start_not_found ? 'true' : 'false',
        $traninfo->mRNA_end_not_found   ? 'true' : 'false',
        $traninfo->author->dbID,
        );
    my $db_id = $sth->{'mysql_insertid'}
        or $self->throw('Failed to get autoincremented ID from transcript_info insert');
    $traninfo->dbID($db_id);
  
    foreach my $rem ($traninfo->remark) {
        $rem->transcript_info_id($traninfo->dbID);
        $self->db->get_TranscriptRemarkAdaptor->store($rem);
    }  
    foreach my $ev (@{$traninfo->get_all_Evidence}) {
	$ev->transcript_info_id($traninfo->dbID);
	$self->db->get_EvidenceAdaptor->store($ev);
    }
}


1;
