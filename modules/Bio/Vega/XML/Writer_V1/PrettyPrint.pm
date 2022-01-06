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

package Bio::Vega::XML::Writer_V1::PrettyPrint;

use Bio::EnsEMBL::Utils::Argument qw ( rearrange );

use strict;
use warnings;

sub new {
  my ($class, @args) = @_;
  my $self=bless {},$class;
  my ($name,$indent,$value)  = rearrange([qw(NAME INDENT VALUE)],@args);
  $self->name($name);
  $self->indent($indent);
  $self->value($value);
  return $self;
}

sub name {
  my ($self, $value) = @_;
  if( defined $value) {
      $self->{'name'} = $value;
  }
  return $self->{'name'};
}

sub value {
  my ($self, $value) = @_;
  if( defined $value) {
      $self->{'value'} = $value;
  }
  return $self->{'value'};
}


sub indent {
  my ($self, $value) = @_;
  if( defined $value) {
      $self->{'indent'} = $value;
  }
  return $self->{'indent'};
}

sub xmlformat {
  my ($self, $value) = @_;
  if( defined $value) {
      unless ($self->{'xmlformat'}){
          $self->{'xmlformat'}='';
      }
      $self->{'xmlformat'}=$self->{'xmlformat'}.$value;
  }
  return $self->{'xmlformat'};
}

sub attribvals {
  my ($self, $value) = @_;
  if (defined $value){
     my $vals = $self->{'attribvals'} ||= [];
     push @$vals, $value;
  }
  return $self->{'attribvals'};
}

sub attribobjs {
  my ($self, $value) = @_;
  if (defined $value){
      unless ($self->{'attribobjs'}){
          $self->{'attribobjs'}=[];
      }
      push @{$self->{'attribobjs'}},$value;
  }
  return $self->{'attribobjs'};
}

1;

__END__

=head1 AUTHOR

Ana Code B<email> anacode@sanger.ac.uk

