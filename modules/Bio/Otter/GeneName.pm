package Bio::Otter::GeneName;

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::Root;

@ISA = qw(Bio::EnsEMBL::Root);

sub new {
  my($class,@args) = @_;

  my $self = bless {}, $class;

  my ($dbid,$name,$gene_info_id)  = $self->_rearrange([qw(
							  DBID
							  NAME
							  GENE_INFO_ID
							  )],@args);

  $self->dbID($dbid);
  $self->name($name);
  $self->gene_info_id($gene_info_id);

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

=head2 gene_info_id

 Title   : gene_info_id
 Usage   : $obj->gene_info_id($newval)
 Function: 
 Example : 
 Returns : value of gene_info_id
 Args    : newvalue (optional)


=cut

sub gene_info_id {
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'gene_info_id'} = $value;
    }
    return $obj->{'gene_info_id'};

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
    my $dbid = "";
    my $name = "";
    my $infoid = "";

    if (defined($self->dbID)) {
	$dbid = $self->dbID;
    }
    if (defined($self->name)) {
	$name = $self->name;
    }
    if (defined($self->gene_info_id)) {
	$infoid = $self->gene_info_id;
    }

    $str .= "DbID    : " . $dbid . "\n";
    $str .= "Name    : " . $name . "\n";
    $str .= "Infoid  : " . $infoid . "\n";

    return $str;

}


sub equals {
    my ($self,$obj) = @_;

    if ($self->name eq $obj->name) {
	return 1;
    } else {
	return 0;
    }
}


1;
