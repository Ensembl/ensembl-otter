package Bio::Otter::CloneInfo;

# clone info file

use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::Root;

@ISA = qw(Bio::EnsEMBL::Root);


sub new {
  my($class,@args) = @_;

  my $self = bless {}, $class;

  my ($dbid,$clone_id,$author,$timestamp,$remark,$keyword)  = 
        $self->_rearrange([qw(DBID CLONE_ID AUTHOR TIMESTAMP REMARK KEYWORD)],@args);

  $self->dbID($dbid);
  $self->clone_id($clone_id);
  $self->author($author);
  $self->timestamp($timestamp);

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



sub dbID{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'dbID'} = $value;
    }
    return $obj->{'dbID'};

}

sub clone_id{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'clone_id'} = $value;
    }
    return $obj->{'clone_id'};

}

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

sub timestamp{
   my ($obj,$value) = @_;
   if( defined $value) {
      $obj->{'timestamp'} = $value;
    }
    return $obj->{'timestamp'};

}

sub equals {
    my ($self,$obj) = @_;     

    if (!defined($obj)) { 
        $self->throw("Need an object to compare with");
    }
    if (!$obj->isa("Bio::Otter::CloneInfo")) {
        $self->throw("[$obj] is not a Bio::Otter::CloneInfo");
    }

    #if ($self->author->equals($obj->author) == 0) {
    #    return 0;
    #}      

    ### These could be made quicker with hashes instead of loops within loops

    my @remark1 = $self->remark;
    my @remark2 = $obj->remark;

    if (scalar(@remark1) != scalar(@remark2)) {
        warn "Different numbers of remarks\n";
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
            warn "Different remarks\n";
            return 0;
        }
    }


    my @old = $self->keyword;
    my @new = $obj->keyword;

    if (@old != @new) {
        warn "Different numbers of keywords\n";
        return 0;
    }

    foreach my $old_key (@old) {
        my $found = 0;

        foreach my $new_key (@new) {
            if ($old_key->equals($new_key)) {
                $found = 1;
            }
        }
        if ($found == 0) {
            printf STDERR "Different keywords: '%s' not found\n", $old_key->name;
            return 0;
        }
    }
   
    return 1;
}


1;


