package Bio::Vega::Gene;

use strict;
use base 'Bio::EnsEMBL::Gene';

sub new {
  my($class,@args) = @_;
  my $self = $class->SUPER::new(@args);
  my ($gene_info)  = $self->_rearrange([qw(INFO)],@args);
  $self->gene_info($gene_info);
  return $self;
}

sub gene_info {
   my ($obj,$value) = @_;
   if( defined $value) {
       if ($value->isa("Bio::Vega::GeneInfo")) {
	   $obj->{'gene_info'} = $value;
       } else {
	   $obj->throw("Argument to gene_info must be a Bio::Vega::GeneInfo object.  Currently is [$value]");
       }
    }
    return $obj->{'gene_info'};
}

1;

__END__

=head1 NAME - Bio::Vega::Gene

=head1 AUTHOR

Sindhu Pillai B<email> sp1@sanger.ac.uk
