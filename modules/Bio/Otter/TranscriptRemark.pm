package Bio::Otter::TranscriptRemark;

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::Root;

@ISA = qw(Bio::EnsEMBL::Root);

sub new {
  my($class,@args) = @_;

  my $self = bless {}, $class;

  my ($dbid,$remark,$info_id)  = $self->_rearrange([qw(
                            DBID
                            REMARK
                            TRANSCRIPT_INFO_ID
                            )],@args);

  $self->dbID($dbid);
  $self->remark($remark);
  $self->transcript_info_id($info_id);

  return $self;
}

=head2 dbID

 Title   : dbID
 Usage   : $obj->dbID($newval)
 Function: 
 Example : 
 Returns : value of dbID
 Args    : newvalue (optional)


=cut

sub dbID{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'dbID'} = $value;
    }
    return $obj->{'dbID'};

}


=head2 remark

  Arg [1]   : none, txt, int, Bio::EnsEMBL::Example
formal_parameter_name
    Additional description lines
    list, listref, hashref
  Function  : testable description
  Returntype: none, txt, int, float, Bio::EnsEMBL::Example
  Exceptions: none
  Caller    : object::methodname or just methodname
  Example   : optional

=cut

sub remark{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'remark'} = $value;
    }
    return $obj->{'remark'};

 }
=head2 transcript_info_id

 Title   : transcript_info_id
 Usage   : $obj->transcript_info_id($newval)
 Function: 
 Example : 
 Returns : value of transcript_info_id
 Args    : newvalue (optional)


=cut

sub transcript_info_id{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'transcript_info_id'} = $value;
    }
    return $obj->{'transcript_info_id'};

}


=head2 toString

 Title   : toString
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub toString{
   my ($self) = shift;

   my $str = "";
   my $dbid = "";
   my $traninfoid = "";

   if (defined($self->dbID)) {
     $dbid = $self->dbID;
   }
   if (defined($self->transcript_info_id)) {
     $traninfoid = $self->transcript_info_id;
   }

   $str .= "DbID       : " . $dbid . "\n";
   $str .= "Traninfoid : " . $traninfoid . "\n";
   $str .= "Remark     : " . $self->remark . "\n";

   return $str;

}


sub equals {
    my ($self,$obj) = @_;

    if (!defined($obj)) {
	$self->throw("Need an object to compare with");
    }
    if (!$obj->isa("Bio::Otter::TranscriptRemark")) {
	$self->throw("Can only compare with a TranscriptRemark object");
    }
    
    if ($self->remark eq $obj->remark) {
	return 1;
    } else {
        print STDERR "FOUND DIFF : " . $self->remark . " : " . $obj->remark . "\n";
	return 0;
    }
}

1;
