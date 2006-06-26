package Bio::Vega::Gene;

use strict;
use Bio::EnsEMBL::Utils::Argument qw ( rearrange );

use base 'Bio::EnsEMBL::Gene';


sub new {
  my($class,@args) = @_;
  my $self = $class->SUPER::new(@args);
  my ($gene_author)  = rearrange([qw(AUTHOR)],@args);
  $self->gene_author($gene_author);
  return $self;
}

sub gene_author {
  my ($obj,$value) = @_;
  if( defined $value) {
	 if ($value->isa("Bio::Vega::Author")) {
		$obj->{'gene_author'} = $value;
	 } else {
		$obj->throw("Argument to gene_author must be a Bio::Vega::Author object.  Currently is [$value]");
	 }
  }
  return $obj->{'gene_author'};
}

sub source  {

  my $self = shift;
  $self->{'source'} = shift if( @_ );
  return ( $self->{'source'} || "havana" );

}

=head2 truncated_flag

Either TRUE or FALSE (1 or 0), it flags whether
the gene contains all its components that are
stored in the database, and hence whether it is
editable in the client.  Defaults to 0.

=cut

sub truncated_flag {
  my( $self, $flag ) = @_;
  if (defined $flag) {
	 $self->{'truncated_flag'} = $flag ? 1 : 0;
  }
  return $self->{'truncated_flag'} || 0;
}


1;

__END__

=head1 NAME - Bio::Vega::Gene

=head1 AUTHOR

Sindhu Pillai B<email> sp1@sanger.ac.uk
