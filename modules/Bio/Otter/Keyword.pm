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

sub dbID{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'dbID'} = $value;
    }
    return $obj->{'dbID'};

}

sub name{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'name'} = $value;
    }
    return $obj->{'name'};

}

sub clone_info_id{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'clone_info_id'} = $value;
    }
    return $obj->{'clone_info_id'};

}

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

sub equals {
    my( $old, $new ) = @_;
    
    return $old->name eq $new->name;
}

1;
