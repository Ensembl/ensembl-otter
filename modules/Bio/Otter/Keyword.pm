package Bio::Otter::Keyword;

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::Root;

@ISA = qw(Bio::EnsEMBL::Root);

sub new {
  my($class,@args) = @_;

  my $self = bless {}, $class;

  my ($dbid,$name,$clone_info_id)  
      = $self->_rearrange([qw(
			      DBID
			      NAME
			      CLONE_INFO_ID
			      )],@args);

  $self->dbID($dbid);
  $self->name($name);
  $self->clone_info_id($clone_info_id);

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

=head2 name

 Title   : name
 Usage   : $obj->name($newval)
 Function: 
 Example : 
 Returns : value of name
 Args    : newvalue (optional)


=cut

sub name{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'name'} = $value;
    }
    return $obj->{'name'};

}

=head2 clone_dbID

 Title   : clone_info_id
 Usage   : $obj->clone_dbID($newval)
 Function: 
 Example : 
 Returns : value of clone_info_id
 Args    : newvalue (optional)


=cut

sub clone_info_id{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'clone_info_id'} = $value;
    }
    return $obj->{'clone_info_id'};

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
    my $clone_info_id = "";

    if (defined($self->dbID)) {
	$dbid = $self->dbID;
    }
    if (defined($self->clone_info_id)) {
	$clone_info_id = $self->clone_info_id;
    }

    $str .= "DbID          : " . $dbid . "\n";
    $str .= "Name          : " . $self->name . "\n";
    $str .= "Clone_info_id : " . $clone_info_id . "\n";

    return $str;

}

1;
