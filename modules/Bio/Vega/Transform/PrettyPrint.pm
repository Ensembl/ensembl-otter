package Bio::Vega::Transform::PrettyPrint;

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

