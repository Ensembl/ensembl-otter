package Bio::Otter::DBSQL::AnnotatedTranscriptAdaptor;

use strict;

use Bio::EnsEMBL::DBSQL::BaseAdaptor;

use Bio::Otter::AnnotatedTranscript;

use Bio::EnsEMBL::DBSQL::TranscriptAdaptor;

use vars qw(@ISA);

@ISA = qw ( Bio::EnsEMBL::DBSQL::TranscriptAdaptor);


sub new {
    my ($class,$dbobj) = @_;

    my $self = {};
    bless $self,$class;

    if( !defined $dbobj || !ref $dbobj ) {
        $self->throw("Don't have a db [$dbobj] for new adaptor");
    }

    $self->db($dbobj);

    return $self;
}

=head2 fetch_by_stable_id

 Title   : fetch_by_stable_id
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub fetch_by_stable_id{
   my ($self,$id) = @_;

   if (!defined($id)) {
       $self->throw("Must enter a transcript id to fetch an AnnotatedTranscript");
   }

   my $sth = $self->prepare(q`
             SELECT tsi1.transcript_id
               FROM transcript_stable_id tsi1 LEFT JOIN transcript_stable_id tsi2 
                 ON tsi1.stable_id = tsi2.stable_id 
                 && tsi1.version < tsi2.version
              WHERE tsi2.stable_id IS NULL
                 && tsi1.stable_id = ?`
                            );
   $sth->execute( $id );

   my $trans;

   if( my $arr = $sth->fetchrow_arrayref ) {
       $trans = $self->fetch_by_dbID( $arr->[0] );
   } else {
       $self->warn( "No Transcript with this stable id found in the database." );
       return undef;
   }

   return $trans;
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
       $self->throw("Must enter a transcript dbID to fetch an AnnotatedTranscript");
   }

   my  $trans = $self->SUPER::fetch_by_dbID($id);

   $self->annotate_transcript($trans);

   return $trans;
   
}

=head2 annotate_transcript

 Title   : annotate_transcript
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub annotate_transcript {
   my ($self,$trans) = @_;

   my $transcript_info_adaptor = $self->db->get_TranscriptInfoAdaptor();
   my $ctia                    = $self->db->get_CurrentTranscriptInfoAdaptor;

   bless $trans, "Bio::Otter::AnnotatedTranscript";

   eval {
     my $infoid = $ctia->fetch_by_transcript_id($trans->stable_id);
     my $info = $transcript_info_adaptor->fetch_by_dbID($infoid);
  
     $trans->transcript_info($info);
   };
   if ($@) {
     print STDERR "Coulnd't fetch info for " . $trans->stable_id . " [$@]\n";
   }
}

=head2 fetch_by_translation_stable_id

 Title   : fetch_by_translation_stable_id
 Usage   :
 Function: fetches the latest translation version for a stable id 
    and returns its annotated transcript
 Example :
 Returns : annotated transcript
 Args    : translation stable id

=cut

sub fetch_by_translation_stable_id{
      my ($self, $transl_stable_id) = @_;

      my $sth = $self->prepare(q`
                   SELECT t.transcript_id
                     FROM transcript t,
                          translation_stable_id tsi1 LEFT JOIN translation_stable_id tsi2 
                       ON tsi1.stable_id = tsi2.stable_id 
                       && tsi1.version < tsi2.version
                    WHERE tsi2.stable_id IS NULL
                       && t.translation_id = tsi1.translation_id
                       && tsi1.stable_id = ?
                          `);
      $sth->execute($transl_stable_id);

      my ($id) = $sth->fetchrow_array;
      if ($id){
          return $self->fetch_by_dbID($id);
      } else {
          return undef;
      }
}


1;

	





