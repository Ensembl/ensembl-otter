package Bio::Otter::GeneInfo;

# clone info file

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::Root;

@ISA = qw(Bio::EnsEMBL::Root);

sub new {
  my($class,@args) = @_;

  my $self = bless {}, $class;

  my ($dbid,$gene_stable_id,$author,$timestamp,$name,$synonym,$remark)  = 
        $self->_rearrange([qw(DBID GENE_STABLE_ID AUTHOR TIMESTAMP NAME SYNONYM REMARK
                            )],@args);

  $self->dbID          ($dbid);
  $self->gene_stable_id($gene_stable_id);
  $self->author        ($author);
  $self->timestamp     ($timestamp);
  $self->name          ($name);

  $self->{_remark}  = [];
  $self->{_synonym} = [];

  if (defined($remark)) {
      if (ref($remark) ne "ARRAY") {
	  $self->throw("Remark argument must be an array ref. Currently is [$remark]\n");
      }

      $self->remark(@$remark);
  }
  if (defined($synonym)) {
      if (ref($synonym) ne "ARRAY") {
	  $self->throw("Remark argument must be an array ref. Currently is [$synonym]\n");
      }

      $self->synonym(@$synonym);
  }
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

=head2 gene_stable_id

 Title   : gene_stable_id
 Usage   : $obj->gene_stable_id($newval)
 Function: 
 Example : 
 Returns : value of gene_stable_id
 Args    : newvalue (optional)


=cut

sub gene_stable_id{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'gene_stable_id'} = $value;
    }
    return $obj->{'gene_stable_id'};

}

=head2 remark

 Title   : remark
 Usage   : $obj->remark($newval)
 Function: 
 Example : 
 Returns : value of remark
 Args    : newvalue (optional)


=cut

sub remark {
    my $obj = shift @_;

    while (my $rem = shift @_) {
      if (defined($rem)) {
        if ($rem->isa("Bio::Otter::GeneRemark")) {
          push(@{$obj->{'_remark'}},$rem);
        } else {
          $obj->throw("Object [$rem] is not a GeneRemark object");
        }
      }
    }
    return @{$obj->{'_remark'}};

}
=head2 remark

 Title   : remark
 Usage   : $obj->remark($newval)
 Function: 
 Example : 
 Returns : value of remark
 Args    : newvalue (optional)


=cut

sub synonym {
    my $self = shift @_;

    while (my $rem = shift @_) {
      if (defined($rem)) {
        if ($rem->isa("Bio::Otter::GeneSynonym")) {
          push(@{$self->{'_synonym'}},$rem);
        } else {
          $self->throw("Argument [$rem] is not a Bio::Otter::GeneSynonym");
        }
      }
    }
    return @{$self->{'_synonym'}};

}

=head2 author

 Title   : author
 Usage   : $obj->author($newval)
 Function: 
 Example : 
 Returns : value of author
 Args    : newvalue (optional)


=cut

sub author{
   my ($self,$value) = @_;

   if( defined $value) {
		 if ($value->isa("Bio::Otter::Author")) {
			 $self->{'author'} = $value;
		 } else {
			 $self->throw("Argument [$value] is not a Bio::Otter::Author");
		 }
	 }
    return $self->{'author'};
}

=head2 timestamp

 Title   : timestamp
 Usage   : $obj->timestamp($newval)
 Function: 
 Example : 
 Returns : value of timestamp
 Args    : newvalue (optional)


=cut

sub timestamp{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'timestamp'} = $value;
    }
    return $obj->{'timestamp'};

}

sub name {
    my ($obj,$value) = @_;

    if (defined($value)) {
	if ($value->isa("Bio::Otter::GeneName")) {
	    $obj->{_name} = $value;
	} else {
	    $obj->throw("[$value] is not a Bio::Otter::GeneName object");
	}
    }
    return $obj->{_name};
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
    my $timestamp = "";

    if (defined($self->dbID)) {
      $dbid = $self->dbID;
    }
    if (defined($self->timestamp)) {
	$timestamp = $self->timestamp;
    }

    $str .= "DbID       : " . $dbid      . "\n";
    $str .= "Stable id  : " . $self->gene_stable_id . "\n";
    $str .= "Timestamp  : " . $timestamp . "\n";

    $str .= "Author info :-\n";

    $str .= $self->author->toString() . "\n";

    $str .= "Gene name :\n";

    $str .= $self->name->toString . "\n";

    $str .= "Gene info synonyms :-\n";

    foreach my $rem ($self->synonym) {
	$str .= $rem->toString . "\n";
    }

    $str .= "Gene info remarks :-\n";

    foreach my $rem ($self->remark) {
	$str .= $rem->toString() . "\n";
    }

    return $str;

}

sub equals {
    my ($self,$obj) = @_;

    if (!defined($obj)) {
	$self->throw("Need an object to compare with");
    }
    if (!$obj->isa("Bio::Otter::GeneInfo")) {
	$self->throw("[$obj] is not a Bio::Otter::GeneInfo");
    }

    if ($self->gene_stable_id ne $obj->gene_stable_id ||
	$self->author->equals($obj->author) == 0) {          
	return 0;
    }

    my @remark1 = $self->remark;
    my @remark2 = $obj->remark;

    if (scalar(@remark1) != scalar(@remark2)) {
      return 0;
    }

    foreach my $rem (@remark1) {
	my $found = 0;
	
	foreach my $rem2 (@remark2) {
	    if ($rem->equals($rem2)) {
		$found = 1;
	    }
	}
	if ($found == 0) {
	    return 0;
	}
    }


    my @syn1 = $self->synonym;
    my @syn2 = $obj->synonym;

    if (scalar(@syn1) != scalar(@syn2)) {
      return 0;
    }

    foreach my $rem (@syn1) {
	my $found = 0;
	
	foreach my $rem2 (@syn2) {
	    if ($rem eq $rem2) {
		$found = 1;
	    }
	}
	if ($found == 0) {
	    return 0;
	}
    }
    
    if (!$self->name->equals($obj->name)) {
	return 0;
    }

    return 1;
}

1;


