
#
# Vega module for Bio::Vega::SequenceFragment
#
package Bio::Vega::SequenceFragment;

use Bio::EnsEMBL::Utils::Argument qw ( rearrange );
use strict;

use Data::Dumper;

sub new {
  my($class,@args) = @_;
  my $self = bless {},$class;
  my ($id,$chromosome,$assembly_start,$assembly_end,$strand,$offset,$author,$remark,$keyword,$accession,$version) =
	 rearrange([qw(
						ID
						CHROMOSOME
						ASSEMBLY_START
						ASSEMBLY_END
						STRAND
						OFFSET
						AUTHOR
						REMARK
						KEYWORD
						ACCESSION
						VERSION
					  )],@args);
  $self->id($id);
  $self->chromosome($chromosome);
  $self->assembly_start($assembly_start);
  $self->assembly_end($assembly_end);
  $self->strand($strand);
  $self->offset($offset);
  $self->author($author);
  $self->remark($remark);
  $self->keyword($keyword);
  $self->accession($accession);
  $self->version($version);

  return $self;
}

sub id{
   my ($self, $value) = @_;
   if (defined $value) {
      $self->{'id'} = $value;
   }
   return $self->{'id'};
}
sub chromosome{
   my ($self, $value) = @_;
   if (defined $value) {
      $self->{'chromosome'} = $value;
   }
   return $self->{'chromosome'};
}
sub assembly_start{
   my ($self, $value) = @_;
   if (defined $value) {
      $self->{'assembly_start'} = $value;
   }
   return $self->{'assembly_start'};
}
sub assembly_end{
   my ($self, $value) = @_;
   if (defined $value) {
      $self->{'assembly_end'} = $value;
   }
   return $self->{'assembly_end'};
}
sub strand{
   my ($self, $value) = @_;
   if (defined $value) {
      $self->{'strand'} = $value;
   }
   return $self->{'strand'};
}
sub offset{
   my ($self, $value) = @_;
   if (defined $value) {
      $self->{'offset'} = $value;
   }
   return $self->{'offset'};
}
sub author{
   my ($self, $value) = @_;
   if (defined $value) {
      $self->{'author'} = $value;
   }
   return $self->{'id'};
}
sub remark{
   my ($self, $value) = @_;
   if (defined $value) {
      $self->{'remark'} = $value;
   }
   return $self->{'remark'};
}
sub keyword{
   my ($self, $value) = @_;
   if (defined $value) {
      $self->{'keyword'} = $value;
   }
   return $self->{'keyword'};
}
sub accession{
   my ($self, $value) = @_;
   if (defined $value) {
      $self->{'accession'} = $value;
   }
   return $self->{'id'};
}
sub version{
   my ($self, $value) = @_;
   if (defined $value) {
      $self->{'version'} = $value;
   }
   return $self->{'version'};
}


1;
