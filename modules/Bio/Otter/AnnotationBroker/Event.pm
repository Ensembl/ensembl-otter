
package Bio::Otter::AnnotationBroker::Event;


use vars qw(@ISA);
use strict;
use Bio::EnsEMBL::Root;

@ISA = qw(Bio::EnsEMBL::Root);

# new is inherieted?

sub new {
  my($caller,@args) = @_;

  my $self = {};

  if(ref $caller) {
    bless $self, ref $caller;
  } else {
    bless $self, $caller;
  }

  my ($type,$old_gene,$new_gene) =

      $self->_rearrange([qw(
			    TYPE
			    OLD
			    NEW
                            )],@args);

  $type || $self->throw("Events must be made with a type");
  $self->type($type);

  $old_gene && $self->old_gene($old_gene);
  $new_gene && $self->new_gene($new_gene);

  return $self;
}


=head2 type

 Title   : type
 Usage   : $type = $event->type
 Function: Get/set on the type of the event
 Returns : string
 Args    : optional new value

=cut

sub type {
    my ($self,$value) = @_;

    if (defined($value)) {
	
	$self->{'type'} = $value
	}
    return $self->{'type'};
}


=head2 old_gene

 Title   : old_gene
 Usage   : $old_gene = $event->old_gene
 Function: Get/set on the old gene 
 Returns : Bio::Otter::Gene
 Args    : optional new value

=cut

sub old_gene {
    my ($self,$value) = @_;

    if (defined($value)) {
	if( !ref $value || !$value->isa('Bio::Otter::AnnotatedGene') ) {
	    $self->throw("[$value] is not an Otter gene");
	}
    $self->{'old'} = $value
    }
    return $self->{'old'};
}


=head2 new_gene

 Title   : new_gene
 Usage   : $new_gene = $event->new_gene
 Function: Get/set on the new gene 
 Returns : Bio::Otter::Gene
 Args    : optional new value

=cut

sub new_gene {
    my ($self,$value) = @_;

    if (defined($value)) {
	if( !ref $value || !$value->isa('Bio::Otter::AnnotatedGene') ) {
	    $self->throw("[$value] is not an Otter gene");
	}
    $self->{'new'} = $value
    }
    return $self->{'new'};
}

sub to_string {
    my $self = shift;
    my $gene;

    if( $self->type eq 'deleted') {
	$gene = $self->old_gene();
    } else {
	$gene = $self->new_gene();
    }

    return sprintf("Event %12s ID %12s",$self->type,$gene->stable_id);
}


1;







