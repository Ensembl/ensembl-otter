package Bio::Otter::CloneInfo;

# clone info file

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::Root;

@ISA = qw(Bio::EnsEMBL::Root);


sub new {
  my($class,@args) = @_;

  my $self = bless {}, $class;

  my ($dbid,$clone_id,$author,$timestamp,$is_active,$remark,$source,$keyword)  = 
        $self->_rearrange([qw(DBID CLONE_ID AUTHOR TIMESTAMP IS_ACTIVE REMARK SOURCE
                              KEYWORD)],@args);

  $self->dbID($dbid);
  $self->clone_id($clone_id);
  $self->author($author);
  $self->timestamp($timestamp);
  $self->is_active($is_active);
  $self->source($source);

  $self->{_remark}   = [];
  $self->{_keyword} = [];


  if (defined($remark)) {
      if (ref($remark) eq "ARRAY") {
          $self->remark(@$remark);
      } else {
          $self->throw("Argument to remark must be an array ref. Currently [$remark]");
      }
  }

  if (defined($keyword)) {
      if (ref($keyword) eq "ARRAY") {
          $self->keyword(@$keyword);
      } else {
          $self->throw("Argument to keyword must be an array ref. Currently [$keyword]");
      }
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

=head2 clone_id

 Title   : clone_id
 Usage   : $obj->clone_id($newval)
 Function: 
 Example : 
 Returns : value of clone_id
 Args    : newvalue (optional)


=cut

sub clone_id{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'clone_id'} = $value;
    }
    return $obj->{'clone_id'};

}

=head2 remark

 Title   : remark
 Usage   : $obj->remark($newval)
 Function: 
 Example : 
 Returns : value of remark
 Args    : newvalue (optional)


=cut

sub remark{
    my $obj = shift @_;

    while (my $rem = shift @_) {
        if ($rem->isa("Bio::Otter::CloneRemark")) {
            push(@{$obj->{'_remark'}},$rem);
        } else {
            $obj->throw("Object [$rem] is not a CloneRemark object");
        }
    }

   return @{$obj->{'_remark'}};

}

=head2 keyword

 Title   : keyword
 Usage   : $obj->keyword($newval)
 Function: 
 Example : 
 Returns : value of keyword
 Args    : newvalue (optional)


=cut

sub keyword{
    my $obj = shift;

    while (my $keyword = shift) {
        if ($keyword->isa("Bio::Otter::Keyword")) {
            push(@{$obj->{'_keyword'}},$keyword);
        } else {
            $obj->throw("Object [$keyword] is not a Keyword object");
        }
    }

   return @{$obj->{'_keyword'}};

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

=head2 is_active

 Title   : is_active
 Usage   :
 Function:
 Example :
 Returns : 
 Args    :


=cut

sub is_active{
   my ($self,$arg) = @_;
	 if (defined($arg)) {
            if ($arg eq 'true') {
	       $arg = 1;
             } elsif ($arg eq 'false') {
               $arg = 0;
             }
	     if ($arg != 1 && $arg != 0) {
		 $self->throw("Argument to is_active must be 0 or 1 . Currently is [$arg]\n");
	      } else {
		 $self->{_is_active} = $arg;
	      }
	 }
	 return $self->{_is_active};

}

=head2 source

 Title   : source
 Usage   : $obj->source($newval)
 Function: 
 Example : 
 Returns : value of source
 Args    : newvalue (optional)


=cut

sub source{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'database_source'} = $value;
    }
    return $obj->{'database_source'};

}

sub equals {
    my ($self,$obj) = @_;     

    if (!defined($obj)) { 
        $self->throw("Need an object to compare with");
    }
    if (!$obj->isa("Bio::Otter::CloneInfo")) {
        $self->throw("[$obj] is not a Bio::Otter::CloneInfo");
    }

    if ($self->accession ne $obj->accession ||
        $self->author->equals($obj->author) == 0) {
        return 0;
    }      

    if ($self->source ne $obj->source) {
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


    my @key1 = $self->keyword;
    my @key2 = $obj->keyword;

    if (scalar(@key1) != scalar(@key2)) {
      return 0;
    }

    foreach my $rem (@key1) {
        my $found = 0;

        foreach my $rem2 (@key2) {
            if ($rem eq $rem2) {
                $found = 1;
            }
        }
        if ($found == 0) {
            return 0;
        }
    }
   
    return 1;
}


1;


