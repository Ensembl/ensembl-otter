package Bio::Otter::GeneRemark;

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::Root;

@ISA = qw(Bio::EnsEMBL::Root);

sub new {
  my($class,@args) = @_;

  my $self = bless {}, $class;

  my ($dbid,$remark,$gene_info_id)  = $self->_rearrange([qw(
                            DBID
                            REMARK
                            GENE_INFO_ID
                            )],@args);

  $self->dbID($dbid);
  $self->remark($remark);
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

=head2 gene_info_id

 Title   : gene_info_id
 Usage   : $obj->gene_info_id($newval)
 Function: 
 Example : 
 Returns : value of gene_info_id
 Args    : newvalue (optional)


=cut

sub gene_info_id{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'gene_info_id'} = $value;
    }
    return $obj->{'gene_info_id'};

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
   my $infoid = "";

   if (defined($self->dbID)) {
      $dbid = $self->dbID;
   }

   if (defined($self->gene_info_id)) {
       $infoid = $self->gene_info_id;
   }

   $str .= "DbID       : " . $dbid . "\n";
   $str .= "Geneinfoid : " . $infoid . "\n";
   $str .= "Remark     : " . $self->remark . "\n";

   return $str;

}


sub equals {
    my ($self,$obj) = @_;

    if (!defined($obj)) {
	$self->throw("Need an object to compare with");
    }
    if (!$obj->isa("Bio::Otter::GeneRemark")) {
	$self->throw("Can only compare with a GeneRemark object");
    }
    
    if ($self->remark eq $obj->remark) {
        #printf STDERR "The same:\n'%s'\n", $obj->remark;
	return 1;
    } else {
        #printf STDERR "Different:\n  '%s'\n  '%s'\n", $self->remark, $obj->remark;
	return 0;
    }
}
	
1;
