package Bio::Otter::Author;

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::Root;

@ISA = qw(Bio::EnsEMBL::Root);

sub new {
  my($class,@args) = @_;

  my $self = bless {}, $class;

  my ($dbid,$name,$email)  = $self->_rearrange([qw(
                            DBID
                            NAME
                            EMAIL
                            )],@args);

  $self->dbID($dbid);
  $self->name($name);
  $self->email($email);

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

=head2 email

 Title   : email
 Usage   : $obj->email($newval)
 Function: 
 Example : 
 Returns : value of email
 Args    : newvalue (optional)


=cut

sub email{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'email'} = $value;
    }
    return $obj->{'email'};

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

    $str .= "DbID    : " . (defined($self->dbID) ? $self->dbID : "undefined")  . "\n";
    $str .= "Name    : " . $self->name . "\n";
    $str .= "Email   : " . $self->email . "\n";

    return $str;

}

sub toXMLString {
    my( $self ) = @_;
    
    my $name  = $self->name  or $self->throw("name not set");
    my $email = $self->email or $self->throw("email not set");
    return "  <author>$name</author>\n  <author_email>$email</author_email>\n";
}

sub equals {
    my ($self,$obj) = @_;

    #if ($self->name eq $obj->name &&
    #$self->email eq $obj->email) {
    if ($self->name eq $obj->name) {
	return 1;
    } else {
	return 0;
    }
}
1;
