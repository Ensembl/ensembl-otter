package Bio::Vega::AuthorGroup;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use base qw(Bio::EnsEMBL::Storable);

sub new {
  my($class,@args) = @_;
  my $self = $class->SUPER::new(@args);
  my ($name,$email)  = rearrange([qw(
                            NAME
                            EMAIL
                            )],@args);

  $self->name($name);
  $self->email($email);
  return $self;
}

=head2 name
 Title   : name
 Usage   : $obj->name($newval)
 Function:
 Example :
 Returns : value of name
 Args    : newvalue (optional), for now...
=cut

sub name{
   my ($self,$value) = @_;
   if( defined $value) {
      $self->{'name'} = $value;
    }
    return $self->{'name'};
}

=head2 email
 Title   : email
 Usage   : $obj->name($newval)
 Function:
 Example :
 Returns : value of name
 Args    : newvalue (optional)
=cut

sub email{
   my ($self,$value) = @_;
   if( defined $value) {
      $self->{'email'} = $value;
    }
    return $self->{'email'};
}



1;

__END__

=head1 NAME - Bio::Vega::AuthorGroup.pm

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk
