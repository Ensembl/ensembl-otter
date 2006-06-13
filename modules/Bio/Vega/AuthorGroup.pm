package Bio::Vega::AuthorGroup;

use strict;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use base qw(Bio::EnsEMBL::Storable);

sub new {
  my($class,@args) = @_;
  my $self = bless {}, $class;
  my ($name)  = rearrange([qw(
                            NAME
                            )],@args);

  $self->name($name);
  return $self;
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
   my ($self,$value) = @_;
   if( defined $value) {
      $self->{'name'} = $value;
    }
    return $self->{'name'};
}



1;

__END__

=head1 NAME - Bio::Vega::AuthorGroup.pm

=head1 AUTHOR

Sindhu K. Pillai B<email> sp1@sanger.ac.uk
