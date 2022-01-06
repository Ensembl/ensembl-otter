=head1 LICENSE

Copyright [2018-2022] EMBL-European Bioinformatics Institute

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

=cut

package Bio::Vega::AuthorGroup;

use strict;
use warnings;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use base qw(Bio::EnsEMBL::Storable);

sub new {
  my ($class, @args) = @_;
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
   my ($self, $value) = @_;
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
   my ($self, $value) = @_;
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

