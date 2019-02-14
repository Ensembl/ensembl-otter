package Bio::Vega::Author;

use Bio::EnsEMBL::Utils::Exception qw ( throw warning );
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use strict;
use warnings;

use base qw(Bio::EnsEMBL::Storable);

sub new {
  my ($class, @args) = @_;
  my $self = $class->SUPER::new(@args);
  my ($name,$email,$group)  = rearrange([qw(
    NAME
    EMAIL
    GROUP
    )],@args);

  $self->name($name);
  $self->email($email);
  $self->group($group); 
  return $self;
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
   my ($self, $value) = @_;
   if( defined $value) {
      $self->{'email'} = $value;
    }
    return $self->{'email'} || $self->name;
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
   my ($self, $value) = @_;
   if( defined $value) {
      $self->{'name'} = $value;
    }
    return $self->{'name'};
}

=head2 group
 Title   : group
 Usage   : $obj->name($newval)
 Function:
 Example :
 Returns : value of author group
 Args    : newvalue (optional)
=cut

sub group{
  my ($self, $value) = @_;
  if( defined $value) {
      $self->{'group'} = $value;
      if (! $value->isa("Bio::Vega::AuthorGroup") ) {
          throw("Argument must be an AuthorGroup object.");
      }
  }
  return $self->{'group'};
}


=head2 new_for_uid($uid)

A shortcut to return a new Author for the OS user ID C<$uid>, using the
conventional representation for "staff".

$uid defaults to C<< $< >>.

=cut

sub new_for_uid {
    my ($class, $uid) = @_;
    $uid ||= $<;
    my $user = getpwuid($uid);
    return $class->new(-NAME => $user, -EMAIL => $user);
}


1;

__END__

=head1 NAME - Bio::Vega::Author.pm

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

