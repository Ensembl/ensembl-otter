package Bio::Otter::TranscriptClass;

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::Root;

@ISA = qw(Bio::EnsEMBL::Root);

sub new {
  my($class,@args) = @_;

  my $self = bless {}, $class;

  my ($dbid,$name,$description)  = $self->_rearrange([qw(
                            DBID
                            NAME
                            DESCRIPTION
                            )],@args);

  $self->dbID($dbid);
  $self->name($name);
  $self->description($description);

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

=head2 description

 Title   : description
 Usage   : $obj->description($newval)
 Function: 
 Example : 
 Returns : value of description
 Args    : newvalue (optional)


=cut

sub description{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'description'} = $value;
    }
    return $obj->{'description'};

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

   my $str   = "";
   my $dbid  = "";
   my $name  = "";
   my $desc  = "";

   if (defined($self->dbID)) {
     $dbid = $self->dbID;
 }
   if (defined($self->name)) {
       $name = $self->name;
   }
   if (defined($self->description)) {
       $desc = $self->description;
   }
  
   $str .= "DbID       : " . $dbid . "\n";
   $str .= "Name       : " . $name . "\n";
   $str .= "Desc       : " . $desc . "\n";

   return $str;

}

sub equals {
    my ($self,$obj) = @_;

    if (!defined($obj)) {
	$self->throw("Need an object to compare with");
    }
    if (!$obj->isa("Bio::Otter::TranscriptClass")) {
	$self->throw("[$obj] is not a Bio::Otter::TranscriptClass");
    }

    if ($self->name eq $obj->name) {
	return 1;
    }
}
1;
